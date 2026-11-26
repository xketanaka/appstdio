class User < ApplicationRecord
  PASSWORD_RESET_EXPIRES_IN = 30.minutes

  # 再設定のトークンはパスワードの salt を含めて署名するので、パスワードを変えると使えなくなる
  has_secure_password reset_token: { expires_in: PASSWORD_RESET_EXPIRES_IN }
  # ログインのセッションに入れる印。同じくパスワードの salt を含めるので、パスワードを変えると他の端末のログインも切れる
  generates_token_for(:session) { password_salt&.last(10) }

  has_many :tenant_users, dependent: :destroy
  has_many :tenants, through: :tenant_users

  # email は citext なので大文字小文字は区別されない。前後の空白のみ落とす。
  normalizes :email, with: ->(email) { email.to_s.strip }

  validates :email,
    presence: true,
    length: { maximum: 255 },
    format: { with: URI::MailTo::EMAIL_REGEXP },
    uniqueness: true
  # 上限 (72文字) は has_secure_password が検証する
  validates :password, length: { minimum: 8 }, allow_nil: true

  # 招待で作られ、まだパスワードを決めていないアカウント（招待を受けるとログインするので、ログインしたことがあれば決めている）
  def never_signed_in?
    last_signed_in_at.nil?
  end

  # パスワード再設定のメールを送る。メールは後で送る
  def send_password_reset
    PasswordResetMailer.reset(to: email, token: password_reset_token,
      expires_at: PASSWORD_RESET_EXPIRES_IN.from_now).deliver_later
  end

  # 再設定のメールの URL から新しいパスワードを決める。メールを受け取れたので、メールアドレスを確かめたことにする
  def reset_password(password:, password_confirmation:)
    # 空のパスワードは has_secure_password が黙って捨てるので、ここで弾く
    if password.empty?
      errors.add(:password, :blank)
      return false
    end
    assign_attributes(password:, password_confirmation:)
    self.email_verified_at ||= Time.current
    save
  end

  def email_verified?
    email_verified_at.present?
  end

  def email_verification_token_valid?
    email_verification_token.present? &&
      email_verification_token_expires_at.present? &&
      email_verification_token_expires_at.future?
  end
end
