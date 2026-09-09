class TenantSelectionsController < ApplicationController
  skip_before_action :tenant_required

  def new
    @tenant_users = sorted_memberships

    # ログイン直後に所属が1件しかなければ選ばせる意味がない。
    # 選択済み（ヘッダの切り替えから来た場合）は1件でも一覧を出す。
    select(@tenant_users.first) if session[:current_tenant_id].blank? && @tenant_users.one?
  end

  def create
    tenant_user = memberships.find_by(tenant_id: params[:tenant_id])

    if tenant_user
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
    redirect_to(session.delete(:return_to) || top_page_path)
  end

  # RLS により、ここで見えるのは自分自身の所属行だけ
  def memberships
    TenantUser.active.where(user_id: session[:current_user_id])
  end

  def sorted_memberships
    memberships.includes(:tenant).order("tenants.name").to_a
  end
end
