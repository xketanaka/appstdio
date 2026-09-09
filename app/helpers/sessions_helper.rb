module SessionsHelper
  # ログイン中のUserインスタンスを返す
  # users は認証情報しか持たないため、実際に参照されたときにだけ読み込む
  def current_user
    return @current_user if defined?(@current_user)

    return if session[:current_user_id].blank?

    @current_user = current_tenant_user&.user || User.find_by(id: session[:current_user_id])
  end

  # 現在操作中のテナントでの所属情報（表示名・権限）を返す（テナント未選択ならnil）
  def current_tenant_user
    @current_tenant_user
  end

  # 現在操作中のTenantインスタンスを返す（テナント未選択ならnil）
  def current_tenant
    @current_tenant_user&.tenant
  end

  # ログイン状況のチェック（ユーザの利用機関の加入状態もチェック）
  # 所属情報が引けていれば users を読まずに判定できる（FK があるので users は必ず存在する）
  def logged_in?
    current_tenant_user.present? || current_user.present?
  end
end
