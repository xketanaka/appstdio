require "test_helper"

# セッション -> コントローラのインスタンス変数 -> DBのテナントコンテキスト
# という受け渡しが繋がっていることを確認する。
class TenantContextFilterTest < ActionController::TestCase
  tests SessionsController

  setup do
    @tenant = Tenant.create!(name: "テナントA")
    @other_tenant = Tenant.create!(name: "テナントB")
    @user = User.create!(email: "a@example.com", password: "password1234")

    @membership = TenantContext.switch(tenant: @tenant) do
      TenantUser.create!(
        tenant: @tenant,
        user: @user,
        display_name: "Aさん",
        role: :admin,
        status: :active,
      )
    end
  end

  teardown do
    TenantContext.clear
  end

  def capture_sql
    statements = []
    subscriber = ActiveSupport::Notifications.subscribe("sql.active_record") do |*, payload|
      statements << payload[:sql] unless payload[:name] == "SCHEMA"
    end
    yield
    statements
  ensure
    ActiveSupport::Notifications.unsubscribe(subscriber)
  end

  test "未ログインなら何も設定されない" do
    get :new

    assert_nil @controller.current_user
    assert_nil @controller.current_tenant_user
    assert_nil @controller.current_tenant
    assert_not @controller.logged_in?
  end

  test "ログイン済みかつテナント選択済みなら所属情報まで解決される" do
    get :new, session: { current_user_id: @user.id, current_tenant_id: @tenant.id }

    assert_equal @user, @controller.current_user
    assert_equal @membership, @controller.current_tenant_user
    assert_equal @tenant, @controller.current_tenant
    assert @controller.current_tenant_user.admin?
    assert_equal "Aさん", @controller.current_tenant_user.display_name
  end

  test "所属していないテナントには切り替えられない" do
    get :new, session: { current_user_id: @user.id, current_tenant_id: @other_tenant.id }

    assert_equal @user, @controller.current_user
    assert_nil @controller.current_tenant_user
    assert_nil @controller.current_tenant
  end

  test "所属が active でなければ切り替えられない" do
    TenantContext.switch(tenant: @tenant) { @membership.update!(status: :suspended) }

    get :new, session: { current_user_id: @user.id, current_tenant_id: @tenant.id }

    assert_equal @user, @controller.current_user
    assert_nil @controller.current_tenant_user
  end

  test "テナント選択済みのリクエストでは users を読まない" do
    sql = capture_sql do
      get :new, session: { current_user_id: @user.id, current_tenant_id: @tenant.id }
    end

    assert_predicate @controller.current_tenant_user, :present?
    assert_no_match(
      /FROM "users"/,
      sql.join("\n"),
      "users は認証情報しか持たないため、リクエストごとに読む必要はない",
    )
    assert_equal 4, sql.size, "実行された SQL:\n#{sql.join("\n")}"
  end

  test "リクエストを抜けたらDBのテナントコンテキストは解除される" do
    get :new, session: { current_user_id: @user.id, current_tenant_id: @tenant.id }

    assert_nil TenantContext.tenant_id
    assert_nil TenantContext.user_id
  end
end
