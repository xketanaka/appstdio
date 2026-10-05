class Tenant < ApplicationRecord
  has_many :tenant_users, dependent: :destroy
  has_many :users, through: :tenant_users

  enum :status, { active: "active", suspended: "suspended" }, validate: true

  validates :name, presence: true, length: { maximum: 255 }

  # テナントは必ずこれで作る。create! だと「全員」グループなどの初期データが無い
  def self.setup!(**attributes)
    transaction do
      tenant = create!(**attributes)
      # groups は RLS が掛かっているので、作るテナントのコンテキストで入れる
      TenantContext.switch(tenant: tenant) do
        Group.create!(tenant: tenant, kind: :everyone, name: I18n.t("groups.everyone"))
      end
      tenant
    end
  end
end
