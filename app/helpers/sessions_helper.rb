module SessionsHelper
  # ログイン中のUserインスタンスを返す
  def current_user
    @current_user
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
  def logged_in?
    current_user.present?
  end
end
