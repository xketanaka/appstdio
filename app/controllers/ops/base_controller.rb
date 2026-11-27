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

    # ログインさせる。ログインの画面と、パスワードを決める画面で使う
    def start_operator_session(operator)
      return_to = session[:ops_return_to]
      reset_session # セッション固定化攻撃への対策
      session[:operator_token] = operator.generate_token_for(:session)
      session[:ops_return_to] = return_to if return_to.present?
      operator.update_column(:last_signed_in_at, Time.current)
    end

    def operator_login_required
      return if @current_operator

      session[:ops_return_to] = request.fullpath if request.get?
      redirect_to ops_login_path
    end
  end
end
