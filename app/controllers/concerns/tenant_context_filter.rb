# リクエストの間だけ、DB のテナントコンテキストを設定する。
#
# ApplicationController に include されるため全てのリクエストで実行される。
# コントローラ側で設定を書き忘れる余地を残さないための構成。
#
# 解決した結果はコントローラのインスタンス変数に持つ。参照は SessionsHelper の
# current_user / current_tenant_user / current_tenant を使う。
module TenantContextFilter
  extend ActiveSupport::Concern

  included do
    around_action :with_tenant_context
  end

  private

  def with_tenant_context
    # users には RLS を掛けていないので、コンテキスト無しで参照できる
    @current_user = authenticated_user

    # 先に user だけ設定する。tenant 側は空になるため、前のリクエストの値が
    # コネクションに残っていてもここで消える。
    # この時点で tenant_users から「自分が所属するテナント」を引けるようになる。
    TenantContext.apply(user: @current_user)

    @current_tenant_user = authenticated_tenant_user
    if @current_tenant_user
      # tenant_id を直接渡す。tenants を引く必要はここでは無い
      TenantContext.apply(tenant: @current_tenant_user.tenant_id, user: @current_user)
    end

    yield
  ensure
    # インスタンス変数はリクエストごとに捨てられるが、DBコネクションは使い回されるため
    # こちらは明示的に解除する
    TenantContext.clear
  end

  def authenticated_user
    return if session[:current_user_id].blank?

    User.find_by(id: session[:current_user_id])
  end

  def authenticated_tenant_user
    return if @current_user.nil? || session[:current_tenant_id].blank?

    # 自分が有効な所属を持つテナントにしか切り替えられない。
    # RLS により、ここで見えるのは自分自身の所属行だけ。
    @current_user.tenant_users.active.find_by(tenant_id: session[:current_tenant_id])
  end
end
