class TenantUser < ApplicationRecord
  belongs_to :tenant
  belongs_to :user

  enum :role, { owner: "owner", admin: "admin", member: "member" }, validate: true
  enum :status, { invited: "invited", active: "active", suspended: "suspended" }, validate: true

  validates :display_name, presence: true, length: { maximum: 255 }
  validates :user_id, uniqueness: { scope: :tenant_id }

  # テナントの管理画面（/management）を使える権限か
  def manager?
    owner? || admin?
  end
end
