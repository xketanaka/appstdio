module Admin
  class BaseController < ApplicationController
    layout "admin"

    skip_around_action :with_tenant_context
    skip_before_action :login_required
    skip_before_action :tenant_required

    before_action :admin_login_required

    helper_method :current_operator

    private

    def current_operator
      @current_operator
    end

    def admin_login_required
      if session[:current_operator_id].present?
        @current_operator = Operator.active.find_by(id: session[:current_operator_id])
      end
      return if @current_operator

      session[:admin_return_to] = request.fullpath if request.get?
      redirect_to admin_login_path
    end
  end
end
