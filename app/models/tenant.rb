class Tenant < ApplicationRecord
  has_many :tenant_users, dependent: :destroy
  has_many :users, through: :tenant_users

  enum :status, { active: "active", suspended: "suspended" }, validate: true

  validates :name, presence: true, length: { maximum: 255 }

  # groups は RLS が掛かっているので、作るテナントのコンテキストで入れる
  after_create do
    TenantContext.switch(tenant: self) do
      Group.create!(tenant: self, kind: :everyone, name: I18n.t("groups.everyone"))
    end
  end
end
