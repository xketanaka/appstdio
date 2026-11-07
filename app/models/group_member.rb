class GroupMember < ApplicationRecord
  belongs_to :tenant
  belongs_to :group
  belongs_to :tenant_user

  enum :role, { member: "member", leader: "leader" }, validate: true

  # 利用停止中の人の所属を除く。所属の行は残してあり、再開すれば戻る
  scope :without_suspended_users, -> { where.not(tenant_user_id: TenantUser.suspended.select(:id)) }

  validates :tenant_user_id, uniqueness: { scope: :group_id }
end
