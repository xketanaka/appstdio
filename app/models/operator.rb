class Operator < ApplicationRecord
  has_secure_password
  # ログインのセッションに入れる印。パスワードの salt を含めて署名するので、パスワードを変えると他の端末のログインも切れる
  generates_token_for(:session) { password_salt&.last(10) }

  enum :status, { invited: "invited", active: "active", suspended: "suspended" }, validate: true

  normalizes :email, with: ->(email) { email.to_s.strip }

  validates :email,
    presence: true,
    length: { maximum: 255 },
    format: { with: URI::MailTo::EMAIL_REGEXP },
    uniqueness: true
  validates :password, length: { minimum: 8 }, allow_nil: true
  validates :display_name, presence: true, length: { maximum: 255 }
end
