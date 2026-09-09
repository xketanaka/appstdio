class SessionsController < ApplicationController
  skip_before_action :login_required, only: [:new, :create]
  skip_before_action :tenant_required, only: [:new, :create, :destroy]

  # ホーム（ログイン済みかつテナント選択済み）
  def index
  end

  def new
    redirect_to select_tenant_path if logged_in?
  end

  def create
    user = User.find_by(email: params[:email].to_s.strip)&.authenticate(params[:password].to_s)

    if user
      start_session(user)
      redirect_to select_tenant_path, notice: t("messages.logged_in")
    else
      # どちらが誤りかは知らせない
      flash.now[:alert] = t("messages.login_failure")
      render :new, status: :unprocessable_entity
    end
  end

  def destroy
    reset_session
    redirect_to login_path, notice: t("messages.logged_out")
  end

  private

  def start_session(user)
    return_to = session[:return_to]
    reset_session # セッション固定化攻撃への対策
    session[:current_user_id] = user.id
    session[:return_to] = return_to if return_to.present?

    user.update_column(:last_signed_in_at, Time.current)
  end
end
