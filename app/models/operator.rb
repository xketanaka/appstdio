class Operator < ApplicationRecord
  has_secure_password

  enum :status, { active: "active", suspended: "suspended" }, validate: true

  normalizes :email, with: ->(email) { email.to_s.strip }

  validates :email,
    presence: true,
    length: { maximum: 255 },
    format: { with: URI::MailTo::EMAIL_REGEXP },
    uniqueness: true
  validates :password, length: { minimum: 8 }, allow_nil: true
  validates :display_name, presence: true, length: { maximum: 255 }
end
