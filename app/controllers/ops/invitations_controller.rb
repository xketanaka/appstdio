module Ops
  # 招待の URL を開いた画面。招待された運営者がパスワードを決めて有効になり、そのままログインする。
  # 招待中の人はログインできないので、ログイン中なら必ず別の運営者。ログアウトして開き直すよう案内する
  class InvitationsController < BaseController
    skip_before_action :operator_login_required
    before_action :set_operator

    def show
    end

    def update
      # 別の運営者でログインしたままでは決めさせない（利用者側の招待と同じ）
      return redirect_to ops_invitation_path(params[:token]) if current_operator

      if @operator.accept_invitation(password: params[:password].to_s, password_confirmation: params[:password_confirmation].to_s)
        start_operator_session(@operator)
        session.delete(:ops_return_to)
        redirect_to ops_root_path, notice: t(".done")
      else
        render :show, status: :unprocessable_entity
      end
    end

    private

    # 使えない招待（改ざん・期限切れ・再送より前の URL・受けた後・取り消し済み）は、どれも同じ案内を出す
    def set_operator
      @operator = Operator.invited.find_by_token_for(:invitation, params[:token])
      render :invalid, status: :not_found unless @operator
    end
  end
end
