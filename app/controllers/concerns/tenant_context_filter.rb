module TenantContextFilter
  extend ActiveSupport::Concern

  included do
    around_action :with_tenant_context
  end

  private

  def with_tenant_context
    user_id = session[:current_user_id]
    tenant_id = session[:current_tenant_id]

    # テナントの設定は DB 接続に書くので、リクエストの間は同じ接続を握り続ける。握らないと、
    # クエリごとにプールから別の接続が渡り、設定の無い接続や、他のリクエストのテナントを設定した接続で走る
    ApplicationRecord.with_connection do
      # tenant_users の RLS は今のテナントの行しか見せないので、セッションのテナントを先に設定してから
      # 自分の所属行を探す。所属していなければ（有効でなければ）見つからないので、テナントの設定を外す
      TenantContext.apply(tenant: tenant_id, user: user_id)
      @current_tenant_user = TenantUser.active.find_by(user_id:) if user_id.present? && tenant_id.present?
      TenantContext.apply(user: user_id) unless @current_tenant_user

      yield
    ensure
      # インスタンス変数と違い DB コネクションは使い回されるので明示的に解除する
      TenantContext.clear
    end
  end
end
