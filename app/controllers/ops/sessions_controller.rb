module Ops
  class SessionsController < BaseController
    skip_before_action :operator_login_required, only: [:new, :create]

    def new
      redirect_to ops_root_path if current_operator
    end

    def create
      operator = Operator.active.find_by(email: params[:email].to_s.strip)&.authenticate(params[:password].to_s)

      if operator
        start_operator_session(operator)
        redirect_to(session.delete(:ops_return_to) || ops_root_path, notice: t("messages.logged_in"))
      else
        # 停止中の運営者が正しいパスワードを入れた場合も同じ応答にする
        flash.now[:alert] = t("messages.login_failure")
        render :new, status: :unprocessable_entity
      end
    end

    def destroy
      reset_session
      redirect_to ops_login_path, notice: t("messages.logged_out")
    end
  end
end
