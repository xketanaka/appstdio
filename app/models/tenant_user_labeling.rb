class TenantUserLabeling < ApplicationRecord
  belongs_to :tenant
  belongs_to :tenant_user
  belongs_to :tenant_user_label

  validates :tenant_user_label_id, uniqueness: { scope: :tenant_user_id }
end
