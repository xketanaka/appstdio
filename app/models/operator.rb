class Operator < ApplicationRecord
  PASSWORD_RESET_EXPIRES_IN = 30.minutes
  INVITATION_EXPIRES_IN = 3.days

  # 再設定のトークンはパスワードの salt を含めて署名するので、パスワードを変えると使えなくなる
  has_secure_password reset_token: { expires_in: PASSWORD_RESET_EXPIRES_IN }
  # ログインのセッションに入れる印。パスワードの salt を含めて署名するので、パスワードを変えると他の端末のログインも切れる
  generates_token_for(:session) { password_salt&.last(10) }
  # 招待の URL のトークン。送った日時を含めるので、再送すると前の URL は使えない
  generates_token_for(:invitation, expires_in: INVITATION_EXPIRES_IN) { invitation_sent_at&.iso8601(6) }

  enum :status, { invited: "invited", active: "active", suspended: "suspended" }, validate: true

  normalizes :email, with: ->(email) { email.to_s.strip }

  validates :email,
    presence: true,
    length: { maximum: 255 },
    format: { with: URI::MailTo::EMAIL_REGEXP },
    uniqueness: true
  validates :password, length: { minimum: 8 }, allow_nil: true
  validates :display_name, presence: true, length: { maximum: 255 }

  # 招待中の運営者を加えて招待メールを送る。パスワードは本人が招待の URL で決めるので、それまでは誰も知らない
  # 値を入れておく（利用者の TenantUser.invite と同じ）。加えられなければ誤りを持たせて返す
  def self.invite(email:, display_name:, by:)
    new(email:, display_name:, status: :invited, password: SecureRandom.base58(32)).tap do |operator|
      operator.send_invitation!(by:) if operator.save
    end
  end

  # 招待メールを送る（再送にも使う）。送った日時を更新するので、前に送った URL は使えなくなる
  def send_invitation!(by:)
    update!(invitation_sent_at: Time.current)
    OperatorMailer.invitation(to: email, inviter_name: by.display_name,
      url: ops_url(:ops_invitation_url, generate_token_for(:invitation)), expires_at: invitation_expires_at).deliver_later
  end

  def invitation_expires_at
    invitation_sent_at + INVITATION_EXPIRES_IN
  end

  # 招待の URL でパスワードを決めて、有効になる
  def accept_invitation(password:, password_confirmation:)
    password_given?(password) && update(password:, password_confirmation:, status: :active)
  end

  # パスワード再設定のメールを送る。メールは後で送る
  def send_password_reset
    OperatorMailer.password_reset(to: email, url: ops_url(:edit_ops_password_reset_url, password_reset_token),
      expires_at: PASSWORD_RESET_EXPIRES_IN.from_now).deliver_later
  end

  # 再設定のメールの URL から新しいパスワードを決める
  def reset_password(password:, password_confirmation:)
    password_given?(password) && update(password:, password_confirmation:)
  end

  private

  # 空のパスワードは has_secure_password が黙って捨てるので、ここで弾く
  def password_given?(password)
    errors.add(:password, :blank) if password.empty?
    password.present?
  end

  # メールに書く運営者画面の URL。メールのジョブは運営者画面のルートを持たないプロセス（利用者側）で動くことも
  # あるので、ここで組み立てて渡す。リクエストのホスト名は Host ヘッダで偽れるので使わず、OPS_URL から作る
  def ops_url(route, token)
    Rails.application.routes.url_helpers.public_send(route, token, **Settings.url_options(Settings.ops_url))
  end
end
