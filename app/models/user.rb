class User < ApplicationRecord
  # 認証主体としての情報のみを保持する。テナント内でのプロフィールは TenantUser を参照。
  has_secure_password

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

  def email_verified?
    email_verified_at.present?
  end

  def password_reset_token_valid?
    password_reset_token.present? &&
      password_reset_token_expires_at.present? &&
      password_reset_token_expires_at.future?
  end

  def email_verification_token_valid?
    email_verification_token.present? &&
      email_verification_token_expires_at.present? &&
      email_verification_token_expires_at.future?
  end
end
