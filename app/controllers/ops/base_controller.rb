module Ops
  class BaseController < ApplicationController
    layout "ops"

    skip_around_action :with_tenant_context
    skip_before_action :login_required
    skip_before_action :tenant_required

    before_action :set_current_operator
    before_action :operator_login_required

    helper_method :current_operator

    private

    def current_operator
      @current_operator
    end

    # 停止中の運営者と、パスワードが変わって印が合わないセッションは、ログインしていない扱いにする
    def set_current_operator
      @current_operator = Operator.active.find_by_token_for(:session, session[:operator_token]) if session[:operator_token]
    end

    def operator_login_required
      return if @current_operator

      session[:ops_return_to] = request.fullpath if request.get?
      redirect_to ops_login_path
    end
  end
end
