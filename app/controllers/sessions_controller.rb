class SessionsController < ApplicationController
  skip_before_action :login_required, only: [:new, :create]
  skip_before_action :tenant_required, only: [:new, :create, :destroy]

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
end
