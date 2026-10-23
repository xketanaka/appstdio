module Management
  class BaseController < ApplicationController
    layout "management"

    before_action :tenant_admin_required

    def tenant_admin_required
      render_not_found unless current_tenant_user.admin_or_owner?
    end

    def render_not_found
      render file: Rails.root.join("public/404.html"), status: :not_found, layout: false
    end
  end
end
