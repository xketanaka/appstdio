class TenantSelectionsController < ApplicationController
  skip_before_action :tenant_required

  def new
    @tenant_users = memberships.includes(:tenant).order("tenants.name")
  end

  def create
    tenant_user = memberships.find_by(tenant_id: params[:tenant_id])

    if tenant_user
      session[:current_tenant_id] = tenant_user.tenant_id
      redirect_to(session.delete(:return_to) || top_page_path)
    else
      flash.now[:alert] = t("messages.tenant_not_available")
      @tenant_users = memberships.includes(:tenant).order("tenants.name")
      render :new, status: :unprocessable_entity
    end
  end

  private

  # RLS により、ここで見えるのは自分自身の所属行だけ
  def memberships
    TenantUser.active.where(user_id: session[:current_user_id])
  end
end
