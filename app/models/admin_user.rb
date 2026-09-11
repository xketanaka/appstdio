class AdminUser < ApplicationRecord
  # サービス提供側の管理者。users を認証主体とし、tenant_users と対になる位置づけ
  belongs_to :user

  enum :status, { active: "active", suspended: "suspended" }, validate: true

  validates :display_name, presence: true, length: { maximum: 255 }
  validates :user_id, uniqueness: true
end
