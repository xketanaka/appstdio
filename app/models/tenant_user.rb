class TenantUser < ApplicationRecord
  # テナント内でのユーザのプロフィール情報。同一ユーザが複数テナントに所属できる。
  belongs_to :tenant
  belongs_to :user

  enum :role, { owner: "owner", admin: "admin", member: "member" }, validate: true
  enum :status, { invited: "invited", active: "active", suspended: "suspended" }, validate: true

  validates :display_name, presence: true, length: { maximum: 255 }
  validates :user_id, uniqueness: { scope: :tenant_id }
end
