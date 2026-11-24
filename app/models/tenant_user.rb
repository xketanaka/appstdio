class TenantUser < ApplicationRecord
  belongs_to :tenant
  belongs_to :user
  belongs_to :suspended_by, class_name: "TenantUser", optional: true
  has_many :group_members
  has_many :labelings, class_name: "TenantUserLabeling"
  has_many :labels, through: :labelings, source: :tenant_user_label
  # 表示名と同じく所属ごとに持つ（組織ごとに別の画像）。AvatarImage で作った画像だけを付ける
  has_one_attached :avatar

  enum :role, { owner: "owner", admin: "admin", member: "member" }, validate: true
  # deleted は利用者管理で削除した所属。行を残すのは、ファイルの作成者などの参照と、マイドライブを残すため
  enum :status, { invited: "invited", active: "active", suspended: "suspended", deleted: "deleted" }, validate: true

  # 停止・削除されていない人（招待中と有効）。一覧・メンバーや共有の相手の候補に出す
  scope :enrolled, -> { where(status: [:invited, :active]) }

  # ログインしている人（app.user_id）の、すべてのテナントでの所属。テナントの選択にだけ使う。
  # tenant_users の RLS は今のテナントの行しか見せないので、所有者の権限で動く関数から引く
  scope :own_memberships, -> { from("own_memberships() AS tenant_users").readonly }

  # 招待の URL のトークン。招待を受ける画面はログイン前でテナントが決まっていないので、RLS のもとで所属を
  # 探す前に切り替えられるよう、テナントの id も入れる。メールの URL に載せるので URL に使える文字にする
  INVITATION_VERIFIER = ActiveSupport::MessageVerifier.new(
    Rails.application.key_generator.generate_key("tenant_user_invitation"), digest: "SHA256", url_safe: true
  )

  # 追加の画面の入力を持つだけで、保存しない（メールアドレスは users にある）
  attribute :email, :string

  validates :display_name, presence: true, length: { maximum: 255 }
  # 削除済みの行は残るので、同じ人を加え直せるよう、一意にするのは削除済み以外の中で
  validates :user_id, uniqueness: { scope: :tenant_id, conditions: -> { not_deleted } }, unless: :deleted?

  # 利用者を招待中として加え、選んだグループにメンバーとして入れ、ラベルを付ける。User はテナントをまたいで共通なので、
  # 同じメールアドレスの User があればそれに所属を足す（パスワードは変えない）。このテナントで削除済みでも、
  # 元の行は戻さずに新しい所属を作る。返すのは所属で、加えられなければ誤りを持たせて返す（保存はしない）。
  # 選べないグループ（Group.assignable_kinds に無い種類・停止中・他テナント。画面からは起きない）が混ざっていたら
  # 見つからない扱いにする
  def self.invite(tenant:, email:, group_ids: [], label_names: [], **attributes)
    groups = Group.where(kind: Group.assignable_kinds(tenant)).active.where(tenant:, id: group_ids).to_a
    raise ActiveRecord::RecordNotFound, "group not selectable" if groups.size != group_ids.uniq.size

    user = User.find_or_initialize_by(email:)
    # 本人がパスワードを決めるまでログインさせないための、誰も知らない値
    user.password = SecureRandom.base58(32) if user.new_record?
    if user.persisted? && not_deleted.exists?(tenant:, user:)
      return new(tenant:, email:, **attributes).tap { it.errors.add(:email, :already_member) }
    end

    tenant_user = new(tenant:, user:, status: :invited, email:, **attributes)
    tenant_user.validate
    user.validate if user.new_record?
    user.errors.each { tenant_user.errors.add(:email, it.message) }
    return tenant_user if tenant_user.errors.any?

    transaction do
      user.save!
      tenant_user.save!
      groups.each { tenant_user.group_members.create!(tenant:, group: it) }
      tenant_user.replace_labels!(label_names)
    rescue ActiveRecord::RecordInvalid => e
      # ラベルの検証（長さ）で落ちたら、ラベルの誤りを所属の誤りとして出す
      e.record.errors.full_messages.each { tenant_user.errors.add(:base, it) } unless e.record == tenant_user
      raise ActiveRecord::Rollback
    end
    tenant_user
  end

  # 招待の URL のトークンから [テナントの id, 所属の id, 送った日時]。改ざん・壊れていれば nil
  def self.decode_invitation_token(token)
    INVITATION_VERIFIER.verified(token.to_s)
  end

  # まだ受けられる招待。招待されたテナントに切り替えた中で呼ぶ。招待中で、最後に送った招待の URL で、
  # 期限内のものだけ（再送すると前の URL は使えない）
  def self.find_acceptable_invitation(id, sent_at)
    tenant_user = invited.includes(:user, :tenant).find_by(id:)
    tenant_user if tenant_user&.invitation_sent_at&.iso8601(6) == sent_at && tenant_user.invitation_expires_at.future?
  end

  # 招待の期限。送った日時から組織設定の日数。日数を変えると送り済みの招待にも効く
  def invitation_expires_at
    invitation_sent_at + tenant.setting.invitation_expiry_days.days
  end

  # 招待メールを送る（再送も同じ）。送った日時を今にするので、前に送った URL は使えなくなる。
  # メールは後で送る。送るジョブはテナントの外で動くので、レコードではなく値で渡す
  def send_invitation!(by:)
    update!(invitation_sent_at: Time.current)
    InvitationMailer.invitation(to: user.email, tenant_name: tenant.name, inviter_name: by.display_name,
      token: INVITATION_VERIFIER.generate([tenant_id, id, invitation_sent_at.iso8601(6)]),
      expires_at: invitation_expires_at).deliver_later
  end

  # 招待を受けて有効にする。メールを受け取れたので、メールアドレスを確かめたことにする。
  # password を渡すと、それをアカウントのパスワードにする（一度もログインしていない人）。
  # パスワードを決められなければ false で、user に誤りを持たせる
  def accept_invitation(password: nil, password_confirmation: nil)
    # 空のパスワードは has_secure_password が黙って捨てるので、ここで弾く
    if password&.empty?
      user.errors.add(:password, :blank)
      return false
    end
    user.assign_attributes(password:, password_confirmation:) if password
    user.email_verified_at ||= Time.current
    transaction do
      raise ActiveRecord::Rollback unless user.save

      update!(status: :active)
      true
    end
  end

  # 利用者管理で、この人が他の人に付けられる権限。オーナーを付けられるのはオーナーだけ
  def assignable_roles
    owner? ? %w[member admin owner] : %w[member admin]
  end

  # 利用者の編集で、この人が target に付けられる権限。オーナーの権限は、オーナーでなければ変えられない
  def role_choices_for(target)
    target.owner? && !owner? ? [target.role] : assignable_roles
  end

  # 表示名・権限などを保存し、ラベルを名前で付け直し、Group.assignable_kinds の種類の有効なグループの中で所属を
  # 付け直す。残すグループでは、グループ管理者の印をそのままにする。停止中のグループと、選べない種類のグループ
  # （プロジェクト機能を利用しないときのプロジェクト）の所属は、画面に出さないので触らない。
  # 有効なオーナーが1人もいなくなる変更は受け付けない。保存できなければ false で、誤りを持たせる。
  # 選べないグループが混ざっていたら（画面からは起きない）見つからない扱いにする
  def update_with(attributes, group_ids:, label_names:)
    group_kinds = Group.assignable_kinds(tenant)
    groups = Group.where(kind: group_kinds).active.where(tenant_id:, id: group_ids).to_a
    raise ActiveRecord::RecordNotFound, "group not selectable" if groups.size != group_ids.uniq.size

    leaving_owner = owner? && active?
    assign_attributes(attributes)
    leaving_owner &&= !(owner? && active?)

    transaction do
      if leaving_owner && !other_active_owner?
        errors.add(:base, :last_owner)
        raise ActiveRecord::Rollback
      end

      save!
      current = GroupMember.where(tenant_user: self).joins(:group).merge(Group.where(kind: group_kinds).active)
      current.where.not(group_id: group_ids).delete_all
      (group_ids - current.pluck(:group_id)).each { group_members.create!(tenant:, group_id: it) }
      replace_labels!(label_names)
      true
    rescue ActiveRecord::RecordInvalid => e
      e.record.errors.full_messages.each { errors.add(:base, it) } unless e.record == self
      raise ActiveRecord::Rollback
    end
  end

  # アバターを、path の画像から作って差し替える（AvatarImage.process）。古い画像は消す。
  # 画像を作れなければ差し替えずに false で、誤りを持たせる
  def replace_avatar(path, crop: nil)
    image = AvatarImage.process(path, crop:)
    # 作った画像の形式と大きさは決まっているので、Active Storage の解析（ジョブ）は要らない
    avatar.attach(io: StringIO.new(image), filename: "avatar.webp", content_type: "image/webp", identify: false,
      metadata: { analyzed: true })
    true
  rescue AvatarImage::Invalid => e
    errors.add(:avatar, e.key, count: AvatarImage::MAX_BYTES / 1.megabyte)
    false
  end

  # ラベルを名前で付け直す。テナントのラベルの一覧に無い名前は、一覧に加える。トランザクションの中で呼ぶこと
  def replace_labels!(names)
    label_ids = names.map { |name| TenantUserLabel.find_or_create_by!(tenant_id:, name:).id }
    labelings.where.not(tenant_user_label_id: label_ids).delete_all
    (label_ids - labelings.pluck(:tenant_user_label_id)).each do |label_id|
      labelings.create!(tenant_id:, tenant_user_label_id: label_id)
    end
  end

  # 利用停止にできるか。有効な人だけ（招待中の人はまだテナントに入れないので、止める代わりに削除する）。
  # 自分は止められない（締め出されないように）。オーナーを止められるのはオーナーだけ
  def suspendable_by?(tenant_user)
    active? && id != tenant_user.id && (!owner? || tenant_user.owner?)
  end

  # 再開できるか。オーナーを再開できるのはオーナーだけ
  def reactivatable_by?(tenant_user)
    suspended? && (!owner? || tenant_user.owner?)
  end

  # 利用停止にし、止めた日時と人を残す。所属グループ・ファイルの権限はそのまま残すので、再開すれば戻る。
  # 有効なオーナーが1人もいなくなるなら止めずに false で、誤りを持たせる
  def suspend(by:)
    transaction do
      if owner? && !other_active_owner?
        errors.add(:base, :last_owner)
        raise ActiveRecord::Rollback
      end

      update!(status: :suspended, suspended_at: Time.current, suspended_by: by)
    end
  end

  def reactivate!
    update!(status: :active, suspended_at: nil, suspended_by: nil)
  end

  # 利用者管理から削除できるか。オーナーと自分自身は削除できない
  def deletable_by?(tenant_user)
    !owner? && id != tenant_user.id
  end

  # 行は消さずに削除済みにし、グループからは外す。削除済みの人を出さないよう、グループの側で
  # 状態を見て回らずに済ませるため。ファイルの権限の行は残す
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

  private

  # 自分の他に有効なオーナーがいるか。同時に2人のオーナーを外して、どちらも「他にいる」と判定しないよう、
  # オーナーの行を id の順に押さえる（順をそろえないと、互いの行を待ってデッドロックになる）。
  # トランザクションの中で呼ぶこと
  def other_active_owner?
    (TenantUser.where(tenant_id:, role: :owner, status: :active).order(:id).lock.ids - [id]).any?
  end
end
