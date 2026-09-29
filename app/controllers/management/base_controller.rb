module Management
  class BaseController < ApplicationController
    layout "management"

    before_action :tenant_manager_required

    def tenant_manager_required
      return if current_tenant_user.manager?

      render file: Rails.root.join("public/404.html"), status: :not_found, layout: false
    end
  end
end
