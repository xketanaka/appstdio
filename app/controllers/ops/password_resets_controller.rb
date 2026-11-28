module Ops
  # 運営者がパスワードを忘れたときの再設定。利用者側（PasswordResetsController）と同じ形で、有効な運営者だけが使える
  class PasswordResetsController < BaseController
    skip_before_action :operator_login_required
    before_action :set_operator, only: [:edit, :update]
    # 他人のメールアドレスへ繰り返し送りつけるのを遅らせる
    rate_limit to: 5, within: 3.minutes, only: :create

    def new
    end

    # 登録の有無は知らせない（どちらも同じ案内を出す）
    def create
      Operator.active.find_by(email: params[:email].to_s.strip)&.send_password_reset
      redirect_to ops_login_path, notice: t(".sent")
    end

    def edit
    end

    def update
      if @operator.reset_password(password: params[:password].to_s, password_confirmation: params[:password_confirmation].to_s)
        start_operator_session(@operator)
        redirect_to(session.delete(:ops_return_to) || ops_root_path, notice: t(".done"))
      else
        render :edit, status: :unprocessable_entity
      end
    end

    private

    # 期限切れ・使用済み（パスワードを変えた後）・改ざん・停止中は、どれも同じ案内を出す
    def set_operator
      @operator = Operator.active.find_by_token_for(:password_reset, params[:token])
      render :invalid, status: :not_found unless @operator
    end
  end
end
