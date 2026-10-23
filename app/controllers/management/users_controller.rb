module Management
  class UsersController < BaseController
    def index
      @tenant_users = TenantUser.where(tenant: current_tenant).includes(:user).order(:id)
    end
  end
end
