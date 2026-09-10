module Admin
  class BaseController < ApplicationController
    layout "admin"

    # 利用テナント側のフィルタは使わない
    skip_around_action :with_tenant_context
    skip_before_action :login_required
    skip_before_action :tenant_required

    before_action :admin_login_required

    helper_method :current_admin_user

    private

    def current_admin_user
      @current_admin_user
    end

    def admin_login_required
      if session[:current_admin_user_id].present?
        @current_admin_user = AdminUser.active.find_by(id: session[:current_admin_user_id])
      end
      return if @current_admin_user

      session[:admin_return_to] = request.fullpath if request.get?
      redirect_to admin_login_path
    end
  end
end
