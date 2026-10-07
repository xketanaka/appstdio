module Files
  class PrivilegedModesController < BaseController
    before_action :admin_or_owner_required

    def create
      session[:files_privileged_tenant_id] = current_tenant.id
      redirect_back_or_to files_root_path
    end

    # 特権でしか開けない画面にいた場合に 404 にならないよう、戻り先はドライブのルートにする
    def destroy
      session.delete(:files_privileged_tenant_id)
      redirect_to files_root_path
    end

    private

    def admin_or_owner_required
      return if current_tenant_user.admin_or_owner?

      render file: Rails.root.join("public/404.html"), status: :not_found, layout: false
    end
  end
end
