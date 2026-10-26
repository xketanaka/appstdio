class TenantUser < ApplicationRecord
  belongs_to :tenant
  belongs_to :user

  enum :role, { owner: "owner", admin: "admin", member: "member" }, validate: true
  enum :status, { invited: "invited", active: "active", suspended: "suspended" }, validate: true

  # ログインしている人（app.user_id）の、すべてのテナントでの所属。テナントの選択にだけ使う。
  # tenant_users の RLS は今のテナントの行しか見せないので、所有者の権限で動く関数から引く
  scope :own_memberships, -> { from("own_memberships() AS tenant_users").readonly }

  validates :display_name, presence: true, length: { maximum: 255 }
  validates :user_id, uniqueness: { scope: :tenant_id }

  def admin_or_owner?
    owner? || admin?
  end
end
