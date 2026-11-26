# 入るテナントを選ぶ。招待中のテナントも並べ、選ぶとその時点で参加する（招待メールの URL を開かなくてよい）
class TenantSelectionsController < ApplicationController
  skip_before_action :tenant_required

  def new
    @tenant_users = sorted_memberships

    # 招待中なら選ぶことが参加になるので、自動では選ばない
    select(@tenant_users.first) if session[:current_tenant_id].blank? && @tenant_users.one? && @tenant_users.first.active?
  end

  def create
    tenant_user = memberships.find_by(tenant_id: params[:tenant_id])

    if tenant_user
      if tenant_user.invited?
        # own_memberships の行は読み取り専用なので、そのテナントに切り替えて引き直す
        TenantContext.switch(tenant: tenant_user.tenant_id, user: current_user) do
          TenantUser.find(tenant_user.id).join!
        end
        flash[:notice] = t(".joined", tenant: tenant_user.tenant.name)
      end
      select(tenant_user)
    else
      flash.now[:alert] = t("messages.tenant_not_available")
      @tenant_users = sorted_memberships
      render :new, status: :unprocessable_entity
    end
  end

  private

  def select(tenant_user)
    session[:current_tenant_id] = tenant_user.tenant_id
    session.delete(:files_privileged_tenant_id)
    redirect_to(session.delete(:return_to) || top_page_path)
  end

  # テナントをまたいで引くのはここだけ（TenantUser.own_memberships）
  def memberships
    TenantUser.own_memberships.enrolled
  end

  def sorted_memberships
    memberships.includes(:tenant).order("tenants.name").to_a
  end
end
