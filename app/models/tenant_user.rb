class TenantUser < ApplicationRecord
  belongs_to :tenant
  belongs_to :user

  enum :role, { owner: "owner", admin: "admin", member: "member" }, validate: true
  enum :status, { invited: "invited", active: "active", suspended: "suspended" }, validate: true

  validates :display_name, presence: true, length: { maximum: 255 }
  validates :user_id, uniqueness: { scope: :tenant_id }

  def admin_or_owner?
    owner? || admin?
  end

  # どれかのグループのグループ管理者か。管理の画面のうちグループ管理だけを開ける
  def group_leader?
    GroupMember.leader.exists?(tenant_user_id: id)
  end
end
