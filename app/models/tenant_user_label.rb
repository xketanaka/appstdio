class TenantUserLabel < ApplicationRecord
  belongs_to :tenant
  has_many :labelings, class_name: "TenantUserLabeling", dependent: :destroy

  normalizes :name, with: ->(name) { name.strip }

  validates :name, presence: true, length: { maximum: 100 }, uniqueness: { scope: :tenant_id }
end
