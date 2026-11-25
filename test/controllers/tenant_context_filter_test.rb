require "test_helper"

class TenantContextFilterTest < ActionController::TestCase
  tests SessionsController

  setup do
    @tenant = Tenant.setup!(name: "テナントA")
    @other_tenant = Tenant.setup!(name: "テナントB")
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
    get :new, session: { user_token: @user.generate_token_for(:session), current_tenant_id: @tenant.id }

    assert_equal @user, @controller.current_user
    assert_equal @membership, @controller.current_tenant_user
    assert_equal @tenant, @controller.current_tenant
    assert @controller.current_tenant_user.admin?
    assert_equal "Aさん", @controller.current_tenant_user.display_name
  end

  test "所属していないテナントには切り替えられない" do
    sql = capture_sql do
      get :new, session: { user_token: @user.generate_token_for(:session), current_tenant_id: @other_tenant.id }
    end

    # 所属行を探すために仮に設定したテナントは、見つからなければアクションの前に外す
    settings = sql.grep(/set_config/)
    assert_includes settings[0], @other_tenant.id
    assert_includes settings[1], "set_config('app.tenant_id', '', false)"

    assert_equal @user, @controller.current_user
    assert_nil @controller.current_tenant_user
    assert_nil @controller.current_tenant
  end

  test "所属が active でなければ切り替えられない" do
    TenantContext.switch(tenant: @tenant) { @membership.update!(status: :suspended) }

    get :new, session: { user_token: @user.generate_token_for(:session), current_tenant_id: @tenant.id }

    assert_equal @user, @controller.current_user
    assert_nil @controller.current_tenant_user
  end

  test "テナント選択済みのリクエストでは、アカウントと所属行を1回ずつ引く" do
    token = @user.generate_token_for(:session)
    sql = capture_sql do
      get :new, session: { user_token: token, current_tenant_id: @tenant.id }
      # 画面などで使っても引き直さない
      @controller.current_user.email
    end

    assert_predicate @controller.current_tenant_user, :present?
    # セッションの印を確かめるアカウントの検索・コンテキストの設定・所属行の検索・解除の4つだけ
    assert_equal 4, sql.size, "実行された SQL:\n#{sql.join("\n")}"
    assert_equal 1, sql.grep(/FROM "users"/).size
  end

  test "パスワードを変えると、それより前のセッションの印では引けない" do
    token = @user.generate_token_for(:session)
    @user.update!(password: "newpassword1")

    get :new, session: { user_token: token, current_tenant_id: @tenant.id }

    assert_nil @controller.current_user
    assert_nil @controller.current_tenant_user
    assert_not @controller.logged_in?
  end

  test "改ざんした印や、利用者の id だけのセッションでは引けない" do
    get :new, session: { user_token: "#{@user.generate_token_for(:session)}x", current_tenant_id: @tenant.id }
    assert_nil @controller.current_user

    get :new, session: { current_user_id: @user.id, current_tenant_id: @tenant.id }
    assert_nil @controller.current_user
  end

  test "リクエストを抜けたらDBのテナントコンテキストは解除される" do
    get :new, session: { user_token: @user.generate_token_for(:session), current_tenant_id: @tenant.id }

    assert_nil TenantContext.tenant_id
    assert_nil TenantContext.user_id
  end
end
