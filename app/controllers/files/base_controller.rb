module Files
  class BaseController < ApplicationController
    before_action :files_enabled_required

    private

    def files_enabled_required
      render_not_found unless current_tenant.files_setting&.enabled?
    end

    def render_not_found
      render file: Rails.root.join("public/404.html"), status: :not_found, layout: false
    end

    def privileged_mode?
      current_tenant_user.admin_or_owner? && session[:files_privileged_tenant_id] == current_tenant.id
    end
  end
end
