module Files
  # ゴミ箱に入れてから3ヶ月（purge_after）たったものを完全に削除する。テナントごとに切り替えて回す
  class PurgeExpiredTrashJob < ApplicationJob
    def perform
      Tenant.find_each do |tenant|
        TenantContext.switch(tenant:) do
          Node.purge!(Node.trash_roots.where(purge_after: ..Time.current).to_a, actor: nil)
        end
      end
    end
  end
end
