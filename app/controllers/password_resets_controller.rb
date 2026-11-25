# パスワードを忘れたときの再設定。メールアドレスを入れると URL をメールで送り、その URL で新しいパスワードを決める
class PasswordResetsController < ApplicationController
  skip_before_action :login_required
  skip_before_action :tenant_required
  before_action :set_user, only: [:edit, :update]
  # 他人のメールアドレスへ繰り返し送りつけるのを遅らせる
  rate_limit to: 5, within: 3.minutes, only: :create

  def new
  end

  # 登録の有無は知らせない（どちらも同じ案内を出す）
  def create
    User.find_by(email: params[:email].to_s.strip)&.send_password_reset
    redirect_to login_path, notice: t(".sent")
  end

  def edit
  end

  def update
    if @user.reset_password(password: params[:password].to_s, password_confirmation: params[:password_confirmation].to_s)
      start_session(@user)
      redirect_to select_tenant_path, notice: t(".done")
    else
      render :edit, status: :unprocessable_entity
    end
  end

  private

  # 期限切れ・使用済み（パスワードを変えた後）・改ざんは、どれも同じ案内を出す
  def set_user
    @user = User.find_by_password_reset_token(params[:token])
    render :invalid, status: :not_found unless @user
  end
end
