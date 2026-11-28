module Ops
  # ログイン中の運営者が、自分のパスワードを変える
  class PasswordsController < BaseController
    def edit
    end

    def update
      changed = current_operator.change_password(current_password: params[:current_password].to_s,
        password: params[:password].to_s, password_confirmation: params[:password_confirmation].to_s)
      if changed
        # パスワードを変えるとセッションの印が合わなくなるので、この端末は印を作り直してログインしたままにする
        start_operator_session(current_operator)
        redirect_to ops_root_path, notice: t(".done")
      else
        render :edit, status: :unprocessable_entity
      end
    end
  end
end
