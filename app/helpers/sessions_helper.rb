module SessionsHelper
  def current_user
    return @current_user if defined?(@current_user)

    return if session[:current_user_id].blank?

    @current_user = current_tenant_user&.user || User.find_by(id: session[:current_user_id])
  end

  def current_tenant_user
    @current_tenant_user
  end

  def current_tenant
    @current_tenant_user&.tenant
  end

  def logged_in?
    current_tenant_user.present? || current_user.present?
  end
end
