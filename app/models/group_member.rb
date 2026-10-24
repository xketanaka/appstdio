class GroupMember < ApplicationRecord
  belongs_to :tenant
  belongs_to :group
  belongs_to :tenant_user

  enum :role, { member: "member", leader: "leader" }, validate: true

  validates :tenant_user_id, uniqueness: { scope: :group_id }
end
