module Ops
  class TenantsController < BaseController
    def index
      @tenants = Tenant
        .left_joins(:tenant_users)
        .select("tenants.*, COUNT(tenant_users.id) AS members_count")
        .group("tenants.id")
        .order(:name)
    end
  end
end
