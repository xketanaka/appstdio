class Group < ApplicationRecord
  # 「全員」グループはメンバーの行を持たない。定義上テナントの所属ユーザ全員なので、
  # 複製するとずれる。所属の解決時に足す
  enum :kind, { department: "department", everyone: "everyone" }, validate: true

  belongs_to :tenant
  belongs_to :parent, class_name: "Group", optional: true
  belongs_to :suspended_by, class_name: "TenantUser", optional: true
  belongs_to :suspension_root, class_name: "Group", optional: true
  has_many :children, class_name: "Group", foreign_key: :parent_id, dependent: :destroy
  has_many :group_members, dependent: :destroy
  has_many :tenant_users, through: :group_members
  has_many :labelings, class_name: "GroupLabeling", dependent: :destroy
  has_many :labels, through: :labelings, source: :group_label

  scope :active, -> { where(suspended_at: nil) }
  scope :suspended, -> { where.not(suspended_at: nil) }

  normalizes :name, with: ->(name) { name.strip }

  validates :name, presence: true, length: { maximum: 255 }
  validate :name_must_be_unique_among_active_siblings
  validate :parent_must_be_selectable

  def self.everyone_of(tenant)
    everyone.find_by!(tenant: tenant)
  end

  # 下位のグループの id（自分は含まない）。停止中も含む。ids は1つでも複数でもよい
  def self.descendant_ids_of(ids)
    connection.select_values(sanitize_sql([<<~SQL.squish, Array(ids)]))
      WITH RECURSIVE descendants(id) AS (
        SELECT id FROM groups WHERE parent_id IN (?)
        UNION
        SELECT groups.id FROM groups JOIN descendants ON groups.parent_id = descendants.id
      )
      SELECT id FROM descendants
    SQL
  end

  # 名前・上位などを保存し、ラベルを名前で付け直す。テナントのラベルの一覧に無い名前は、一覧に加える。
  # ラベルの検証（長さ）で落ちたらグループの保存も戻し、ラベルの誤りをグループの誤りとして出す。保存できなければ false
  def save_with_labels(names)
    transaction do
      save!
      label_ids = names.map { |name| GroupLabel.find_or_create_by!(tenant:, name:).id }
      labelings.where.not(group_label_id: label_ids).delete_all
      (label_ids - labelings.pluck(:group_label_id)).each do |label_id|
        labelings.create!(tenant:, group_label_id: label_id)
      end
      true
    rescue ActiveRecord::RecordInvalid => e
      e.record.errors.full_messages.each { errors.add(:base, it) } unless e.record == self
      raise ActiveRecord::Rollback
    end
  end

  # メンバーを付け直す。roles は { tenant_user_id => "member" / "leader" }。保存できなければ false で、
  # 誤りはグループの誤りとして出す。新しく加える人は、テナントの所属のうち有効・招待中の人に限り、
  # それ以外が混ざっていたら（画面からは起きない）見つからない扱いにする
  def replace_members(roles)
    added_ids = roles.keys - group_members.pluck(:tenant_user_id)
    addable = TenantUser.where(tenant_id:, id: added_ids, status: [:active, :invited]).count
    raise ActiveRecord::RecordNotFound, "tenant_user not addable" if addable != added_ids.size

    transaction do
      group_members.where.not(tenant_user_id: roles.keys).delete_all
      roles.each do |tenant_user_id, role|
        group_members.find_or_initialize_by(tenant_user_id:).update!(tenant:, role:)
      end
      true
    rescue ActiveRecord::RecordInvalid => e
      e.record.errors.full_messages.each { errors.add(:base, it) }
      raise ActiveRecord::Rollback
    end
  end

  def suspended?
    suspended_at.present?
  end

  # 利用停止にする。自分（起点）と、まだ有効な下位のすべての行に、停止日時・停止した人・
  # その時点の上位の名前の並び・起点を書き込む。先に別の操作で停止していた下位は、その起点のまま残す
  def suspend!(by:)
    descendants = Group.where(id: Group.descendant_ids_of(id)).to_a
    by_id = descendants.index_by(&:id).merge(id => self)
    paths = { id => self_and_ancestors.drop(1).reverse.map(&:name) }
    path_of = ->(group) { paths[group.id] ||= path_of.(by_id[group.parent_id]) + [by_id[group.parent_id].name] }
    now = Time.current

    transaction do
      [self, *descendants.reject(&:suspended?)].each do |group|
        group.update_columns(suspended_at: now, suspended_by_id: by.id, suspended_path: path_of.(group),
          suspension_root_id: id, updated_at: now)
      end
    end
  end

  # 再開できないわけ。[訳のキー, 差し込む値] か、再開できるなら nil
  def reactivation_blocker
    return [:not_root, { name: suspension_root.name }] if suspension_root_id != id

    suspended_ancestor = self_and_ancestors.drop(1).find(&:suspended?)
    return [:ancestor_suspended, { name: suspended_ancestor.name }] if suspended_ancestor
    return [:name_taken, {}] if Group.active.where(tenant_id:, parent_id:, name:).exists?

    nil
  end

  # 起点を再開する。この停止の操作で一緒に止まった行だけを有効に戻す。再開できなければ false
  def reactivate
    return false if reactivation_blocker

    Group.where(suspension_root_id: id).update_all(suspended_at: nil, suspended_by_id: nil, suspended_path: nil,
      suspension_root_id: nil, updated_at: Time.current)
    reload
    true
  end

  def self_and_ancestors
    chain = [self]
    node = parent
    while node && chain.exclude?(node)
      chain << node
      node = node.parent
    end
    chain
  end

  private

  # 停止中のグループとは重なってよい（停止した部署と同じ名前で作り直せるように）。
  # 所有者ロール（運営者画面）は RLS を素通りするので、テナントでも絞る
  def name_must_be_unique_among_active_siblings
    return if suspended?

    errors.add(:name, :taken) if Group.active.where(tenant_id:, parent_id:, name:).where.not(id:).exists?
  end

  # 「全員」と停止中は上位にできない。自分と自分の下位を上位にすると循環する
  def parent_must_be_selectable
    # 他のテナントのグループは RLS で見えず、parent が nil になる
    return errors.add(:parent, :invalid) if parent_id && parent.nil?
    return if parent.nil?

    cyclic = persisted? && parent.self_and_ancestors.include?(self)
    errors.add(:parent, :invalid) if parent.everyone? || parent.suspended? || cyclic
  end
end
