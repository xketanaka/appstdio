module Management
  class UsersController < BaseController
    def index
      @tenant_users = TenantUser.includes(:user).order(:id)
    end
  end
end
