class TenantUser < ApplicationRecord
  belongs_to :tenant
  belongs_to :user
  has_many :group_members

  enum :role, { owner: "owner", admin: "admin", member: "member" }, validate: true
  # deleted は利用者管理で削除した所属。行を残すのは、ファイルの作成者などの参照と、マイドライブを残すため
  enum :status, { invited: "invited", active: "active", suspended: "suspended", deleted: "deleted" }, validate: true

  # ログインしている人（app.user_id）の、すべてのテナントでの所属。テナントの選択にだけ使う。
  # tenant_users の RLS は今のテナントの行しか見せないので、所有者の権限で動く関数から引く
  scope :own_memberships, -> { from("own_memberships() AS tenant_users").readonly }

  # 追加の画面の入力を持つだけで、保存しない（メールアドレスは users にある）
  attribute :email, :string

  validates :display_name, presence: true, length: { maximum: 255 }
  validates :user_id, uniqueness: { scope: :tenant_id }

  # 利用者を招待中として加え、選んだグループにメンバーとして入れる。User はテナントをまたいで共通なので、
  # 同じメールアドレスの User があればそれに所属を足す（パスワードは変えない）。このテナントで削除済みなら、
  # 同じ行を戻す。返すのは所属で、加えられなければ誤りを持たせて返す（保存はしない）。
  # 選べないグループ（停止中・「全員」・他テナント。画面からは起きない）が混ざっていたら見つからない扱いにする
  def self.invite(tenant:, email:, group_ids: [], **attributes)
    groups = Group.department.active.where(tenant:, id: group_ids).to_a
    raise ActiveRecord::RecordNotFound, "group not selectable" if groups.size != group_ids.uniq.size

    user = User.find_or_initialize_by(email:)
    # 本人がパスワードを決めるまでログインさせないための、誰も知らない値
    user.password = SecureRandom.base58(32) if user.new_record?
    tenant_user = (find_by(tenant:, user:) if user.persisted?) || new(tenant:, user:)
    unless tenant_user.new_record? || tenant_user.deleted?
      return new(tenant:, email:, **attributes).tap { it.errors.add(:email, :already_member) }
    end

    tenant_user.assign_attributes(status: :invited, email:, **attributes)
    tenant_user.validate
    user.validate if user.new_record?
    user.errors.each { tenant_user.errors.add(:email, it.message) }
    return tenant_user if tenant_user.errors.any?

    transaction do
      user.save!
      tenant_user.save!
      groups.each { tenant_user.group_members.create!(tenant:, group: it) }
    end
    tenant_user
  end

  # 利用者管理で、この人が他の人に付けられる権限。オーナーを付けられるのはオーナーだけ
  def assignable_roles
    owner? ? %w[member admin owner] : %w[member admin]
  end

  # 利用者管理から削除できるか。オーナーと自分自身は削除できない
  def deletable_by?(tenant_user)
    !owner? && id != tenant_user.id
  end

  # 行は消さずに削除済みにし、グループからは外す。削除済みの人を出さないよう、グループの側で
  # 状態を見て回らずに済ませるため。ファイルの権限の行は残す（追加し直して戻したときに元に戻る）
  def mark_deleted!
    transaction do
      GroupMember.where(tenant_user: self).delete_all
      update!(status: :deleted)
    end
  end

  def admin_or_owner?
    owner? || admin?
  end

  # どれかのグループのグループ管理者か。管理の画面のうちグループ管理だけを開ける
  def group_leader?
    GroupMember.leader.exists?(tenant_user_id: id)
  end
end
