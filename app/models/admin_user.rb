class AdminUser < ApplicationRecord
  belongs_to :user

  enum :status, { active: "active", suspended: "suspended" }, validate: true

  validates :display_name, presence: true, length: { maximum: 255 }
  validates :user_id, uniqueness: true
end
