module Files
  module Api
    class PrivilegedModesController < BaseController
      before_action :admin_or_owner_required

      def create
        session[:files_privileged_tenant_id] = current_tenant.id
        head :no_content
      end

      def destroy
        session.delete(:files_privileged_tenant_id)
        head :no_content
      end

      private

      def admin_or_owner_required
        render_not_found unless current_tenant_user.admin_or_owner?
      end
    end
  end
end
