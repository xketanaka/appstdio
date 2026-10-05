class Group < ApplicationRecord
  # 「全員」グループはメンバーの行を持たない。定義上テナントの所属ユーザ全員なので、
  # 複製するとずれる。所属の解決時に足す
  enum :kind, { department: "department", everyone: "everyone" }, validate: true

  belongs_to :tenant
  belongs_to :parent, class_name: "Group", optional: true
  has_many :children, class_name: "Group", foreign_key: :parent_id, dependent: :destroy
  has_many :group_members, dependent: :destroy
  has_many :tenant_users, through: :group_members

  validates :name, presence: true, length: { maximum: 255 }
  validate :parent_must_not_be_self_or_descendant

  def self.everyone_of(tenant)
    everyone.find_by(tenant: tenant) || everyone.create_or_find_by!(tenant: tenant) do |group|
      group.name = I18n.t("groups.everyone")
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

  def parent_must_not_be_self_or_descendant
    return if parent.nil?
    return unless persisted?

    errors.add(:parent, :invalid) if parent.self_and_ancestors.include?(self)
  end
end
