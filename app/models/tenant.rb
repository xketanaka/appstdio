class Tenant < ApplicationRecord
  has_many :tenant_users, dependent: :destroy
  has_many :users, through: :tenant_users

  enum :status, { active: "active", suspended: "suspended" }, validate: true

  validates :name, presence: true, length: { maximum: 255 }
end
