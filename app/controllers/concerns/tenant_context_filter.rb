# リクエストの間だけ DB のテナントコンテキストを設定し、解決した結果を
# @current_tenant_user に置く。
# 参照は SessionsHelper の current_user / current_tenant_user / current_tenant を使う。
module TenantContextFilter
  extend ActiveSupport::Concern

  included do
    around_action :with_tenant_context
  end

  private

  def with_tenant_context
    # 順序に依存している。tenant_users には RLS が掛かっているため、
    # 先に app.user_id を設定しないと自分の所属行すら見えない
    TenantContext.apply(user: session[:current_user_id])

    @current_tenant_user = authenticated_tenant_user
    if @current_tenant_user
      TenantContext.apply(
        tenant: @current_tenant_user.tenant_id,
        user: @current_tenant_user.user_id,
      )
    end

    yield
  ensure
    # インスタンス変数と違い DB コネクションは使い回されるので明示的に解除する
    TenantContext.clear
  end

  def authenticated_tenant_user
    return if session[:current_user_id].blank? || session[:current_tenant_id].blank?

    TenantUser.active.find_by(
      tenant_id: session[:current_tenant_id],
      user_id: session[:current_user_id],
    )
  end
end
