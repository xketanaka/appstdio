class Tenant < ApplicationRecord
  has_many :tenant_users, dependent: :destroy
  has_many :users, through: :tenant_users
  has_one :setting, class_name: "TenantSetting", dependent: :destroy
  has_one :files_setting, class_name: "Files::Setting", dependent: :destroy

  enum :status, { active: "active", suspended: "suspended" }, validate: true

  validates :name, presence: true, length: { maximum: 255 }

  # テナントは必ずこれで作る。create! だと「全員」グループや設定の行などの初期データが無い
  def self.setup!(**attributes)
    transaction do
      tenant = create!(**attributes)
      # groups は RLS が掛かっているので、作るテナントのコンテキストで入れる
      TenantContext.switch(tenant: tenant) do
        Group.create!(tenant: tenant, kind: :everyone, name: I18n.t("groups.everyone"))
        TenantSetting.create!(tenant: tenant)
        Files::Setting.create!(tenant: tenant, enabled: true)
      end
      tenant
    end
  end
end
