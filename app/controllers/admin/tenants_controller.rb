module Admin
  class TenantsController < BaseController
    def index
      # 所属数はテナントを跨いで数える。appstdio_admin のポリシーでのみ可能
      @tenants = Tenant
        .left_joins(:tenant_users)
        .select("tenants.*, COUNT(tenant_users.id) AS members_count")
        .group("tenants.id")
        .order(:name)
    end
  end
end
