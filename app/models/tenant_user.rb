class TenantUser < ApplicationRecord
  belongs_to :tenant
  belongs_to :user

  enum :role, { owner: "owner", admin: "admin", member: "member" }, validate: true
  # deleted は利用者管理で削除した所属。行を残すのは、ファイルの作成者などの参照と、マイドライブを残すため
  enum :status, { invited: "invited", active: "active", suspended: "suspended", deleted: "deleted" }, validate: true

  # ログインしている人（app.user_id）の、すべてのテナントでの所属。テナントの選択にだけ使う。
  # tenant_users の RLS は今のテナントの行しか見せないので、所有者の権限で動く関数から引く
  scope :own_memberships, -> { from("own_memberships() AS tenant_users").readonly }

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
