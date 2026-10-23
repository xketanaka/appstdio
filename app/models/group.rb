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

  # 下位のグループの id（自分は含まない）。停止中も含む
  def self.descendant_ids_of(id)
    connection.select_values(sanitize_sql([<<~SQL.squish, id]))
      WITH RECURSIVE descendants(id) AS (
        SELECT id FROM groups WHERE parent_id = ?
        UNION
        SELECT groups.id FROM groups JOIN descendants ON groups.parent_id = descendants.id
      )
      SELECT id FROM descendants
    SQL
  end

  # ラベルを名前で付け直す。テナントのラベルの一覧に無い名前は、一覧に加える
  def replace_labels!(names)
    label_ids = names.map { |name| GroupLabel.find_or_create_by!(tenant:, name:).id }
    labelings.where.not(group_label_id: label_ids).delete_all
    (label_ids - labelings.pluck(:group_label_id)).each do |label_id|
      labelings.create!(tenant:, group_label_id: label_id)
    end
  end

  # メンバーを付け直す。roles は { tenant_user_id => "member" / "leader" }。
  # 新しく加える人は、テナントの所属のうち有効・招待中の人に限る
  def replace_members!(roles)
    added_ids = roles.keys - group_members.pluck(:tenant_user_id)
    addable = TenantUser.where(tenant_id:, id: added_ids, status: [:active, :invited]).count
    raise ActiveRecord::RecordNotFound, "tenant_user not addable" if addable != added_ids.size

    group_members.where.not(tenant_user_id: roles.keys).delete_all
    roles.each do |tenant_user_id, role|
      group_members.find_or_initialize_by(tenant_user_id:).update!(tenant:, role:)
    end
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
    return if suspended_at

    errors.add(:name, :taken) if Group.active.where(tenant_id:, parent_id:, name:).where.not(id:).exists?
  end

  # 「全員」と停止中は上位にできない。自分と自分の下位を上位にすると循環する
  def parent_must_be_selectable
    return if parent.nil?

    cyclic = persisted? && parent.self_and_ancestors.include?(self)
    errors.add(:parent, :invalid) if parent.everyone? || parent.suspended_at || cyclic
  end
end
