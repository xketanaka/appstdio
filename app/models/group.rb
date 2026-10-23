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

  validates :name, presence: true, length: { maximum: 255 }
  validate :parent_must_not_be_self_or_descendant

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

  def parent_must_not_be_self_or_descendant
    return if parent.nil?
    return unless persisted?

    errors.add(:parent, :invalid) if parent.self_and_ancestors.include?(self)
  end
end
