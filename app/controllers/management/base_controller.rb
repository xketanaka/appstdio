module Management
  class BaseController < ApplicationController
    layout "management"

    before_action :tenant_admin_required

    def tenant_admin_required
      return if current_tenant_user.admin_or_owner?

      render file: Rails.root.join("public/404.html"), status: :not_found, layout: false
    end
  end
end
