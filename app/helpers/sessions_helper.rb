module SessionsHelper
  # ログイン中のアカウントと所属は、リクエストの始めに TenantContextFilter が決める
  def current_user
    @current_user
  end

  def current_tenant_user
    @current_tenant_user
  end

  def current_tenant
    @current_tenant_user&.tenant
  end

  def logged_in?
    current_user.present?
  end
end
