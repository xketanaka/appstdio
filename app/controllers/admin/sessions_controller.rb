module Admin
  class SessionsController < BaseController
    skip_before_action :admin_login_required, only: [:new, :create]

    def new
      redirect_to admin_root_path if session[:current_operator_id].present?
    end

    def create
      operator = Operator.active.find_by(email: params[:email].to_s.strip)&.authenticate(params[:password].to_s)

      if operator
        return_to = session[:admin_return_to]
        reset_session # セッション固定化攻撃への対策
        session[:current_operator_id] = operator.id
        operator.update_column(:last_signed_in_at, Time.current)

        redirect_to(return_to.presence || admin_root_path, notice: t("messages.logged_in"))
      else
        # 停止中のシステム管理者が正しいパスワードを入れた場合も同じ応答にする
        flash.now[:alert] = t("messages.login_failure")
        render :new, status: :unprocessable_entity
      end
    end

    def destroy
      reset_session
      redirect_to admin_login_path, notice: t("messages.logged_out")
    end
  end
end
