module Files
  # 保持日数を過ぎた古い版の中身を消す。保持日数を決めていない（無制限の）テナントは何もしない
  class PurgeExpiredVersionsJob < ApplicationJob
    def perform
      Tenant.find_each do |tenant|
        TenantContext.switch(tenant:) do
          retention_days = tenant.files_setting&.version_retention_days
          Version.purge_expired!(tenant_id: tenant.id, retention_days:) if retention_days
        end
      end
    end
  end
end
