# 招待の URL を開いた画面。招待で作られた新しいアカウントが、パスワードを決めて参加する。ログインしていなくても開ける。
# URL のトークンから招待されたテナントを決め、その中で所属を探す。
# パスワードのあるアカウントは、ログインして組織の選択から参加する（TenantSelectionsController）ので、ここでは案内だけ出す
class InvitationsController < ApplicationController
  skip_before_action :login_required
  skip_before_action :tenant_required
  before_action :set_invitation

  def show
  end

  def update
    user = @tenant_user.user
    return redirect_to invitation_path(params[:token]) if logged_in? || !user.never_signed_in?

    accepted = in_invited_tenant do
      @tenant_user.accept_invitation(password: params[:password].to_s,
        password_confirmation: params[:password_confirmation].to_s)
    end

    if accepted
      start_session(user)
      session.delete(:return_to)
      session[:current_tenant_id] = @tenant_user.tenant_id
      redirect_to top_page_path, notice: t(".done", tenant: @tenant_user.tenant.name)
    else
      render :show, status: :unprocessable_entity
    end
  end

  private

  # 使えない招待（改ざん・期限切れ・再送より前の URL・参加済み・削除済み）は、どれも同じ案内を出す
  def set_invitation
    tenant_id, id, sent_at = TenantUser.decode_invitation_token(params[:token])
    @tenant_user = in_invited_tenant(tenant_id) { TenantUser.find_acceptable_invitation(id, sent_at) } if tenant_id
    if @tenant_user
      @expires_at = in_invited_tenant { @tenant_user.invitation_expires_at }
    else
      render :invalid, status: :not_found
    end
  end

  # 招待されたテナントに切り替えて DB を触る。画面の描画はこの外で行う（画面の枠はログイン中のテナントの設定を読むので）
  def in_invited_tenant(tenant_id = @tenant_user.tenant_id, &)
    TenantContext.switch(tenant: tenant_id, user: session[:current_user_id], &)
  end
end
