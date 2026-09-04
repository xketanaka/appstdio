class Tenant < ApplicationRecord
  # 主キーは外部に露出する識別子のためUUIDv7 (DB側の uuidv7() で採番)
  has_many :tenant_users, dependent: :destroy
  has_many :users, through: :tenant_users

  enum :status, { active: "active", suspended: "suspended" }, validate: true

  validates :name, presence: true, length: { maximum: 255 }
end
