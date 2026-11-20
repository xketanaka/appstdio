# 招待を受ける画面。ログインしていなくても開ける。URL のトークンから招待されたテナントを決め、その中で所属を探す
class InvitationsController < ApplicationController
  skip_before_action :login_required
  skip_before_action :tenant_required
  before_action :set_invitation
  # パスワードを当てようと繰り返すのを遅らせる
  rate_limit to: 10, within: 3.minutes, only: :update

  # 開いた人によって出し分ける（app/views/invitations/show.html.erb）。招待された本人でログインしている、
  # 別の人でログインしている、ログインしていなくて一度もログインしたことがない（パスワードを決める）・ある（今のパスワードを入れる）
  def show
  end

  def update
    user = @tenant_user.user
    accepted =
      if session[:current_user_id] == user.id
        in_invited_tenant { @tenant_user.accept_invitation }
      elsif session[:current_user_id].present?
        false
      elsif user.never_signed_in?
        in_invited_tenant do
          @tenant_user.accept_invitation(password: params[:password].to_s,
            password_confirmation: params[:password_confirmation].to_s)
        end
      elsif user.authenticate(params[:password].to_s)
        in_invited_tenant { @tenant_user.accept_invitation }
      else
        flash.now[:alert] = t(".wrong_password")
        false
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
    @tenant_user = in_invited_tenant(tenant_id) { TenantUser.open_invitation(id, sent_at) } if tenant_id
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
