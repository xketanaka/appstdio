require "test_helper"

# 管理画面は appstdio_admin で接続し、ルーティングも利用テナント側と入れ替わる。
# 通常の bin/rails test では動かないので、bin/rails test:admin で実行する。
class AdminConsoleTest < ActionDispatch::IntegrationTest
  PASSWORD = "password1234".freeze

  setup do
    unless Rails.configuration.x.admin_console
      skip("管理画面のテストは bin/rails test:admin で実行する")
    end

    @tenant_a = Tenant.create!(name: "テナントA")
    @tenant_b = Tenant.create!(name: "テナントB")

    @operator = User.create!(email: "operator@example.com", password: PASSWORD)
    @admin_user = AdminUser.create!(user: @operator, display_name: "運用担当", status: :active)

    @tenant_member = User.create!(email: "member@example.com", password: PASSWORD)
    TenantUser.create!(
      tenant: @tenant_a, user: @tenant_member, display_name: "Aさん", status: :active,
    )
  end

  test "管理者としてログインしテナント一覧を見る" do
    get admin_root_path
    assert_redirected_to admin_login_path

    post admin_login_path, params: { email: @operator.email, password: PASSWORD }
    assert_redirected_to admin_root_path

    follow_redirect!
    assert_response :success
    assert_select ".table tbody tr", 2
    assert_select ".table td", text: "テナントA"
    assert_select ".table td", text: "テナントB"
  end

  test "所属ユーザ数はテナントを跨いで数えられる" do
    login_as_admin
    get admin_root_path

    assert_select ".table tbody tr:first-child .table__number", text: "1"
    assert_select ".table tbody tr:last-child .table__number", text: "0"
  end

  test "テナントコンテキストを設定しなくても所属情報が見える" do
    # 利用テナント側のロールでは 0 件になる範囲
    assert_nil TenantContext.tenant_id
    assert_equal 1, TenantUser.count
  end

  test "管理者でないユーザは正しいパスワードでも入れない" do
    post admin_login_path, params: { email: @tenant_member.email, password: PASSWORD }

    assert_response :unprocessable_entity
    assert_select ".alert", text: /メールアドレスまたはパスワードが違います/
    assert_nil session[:current_admin_user_id]
  end

  test "停止中の管理者はログインできない" do
    @admin_user.update!(status: :suspended)

    post admin_login_path, params: { email: @operator.email, password: PASSWORD }
    assert_response :unprocessable_entity
    assert_nil session[:current_admin_user_id]
  end

  test "ログイン前に見ようとしたページへ戻る" do
    get admin_tenants_path
    assert_redirected_to admin_login_path

    post admin_login_path, params: { email: @operator.email, password: PASSWORD }
    assert_redirected_to admin_tenants_path
  end

  test "ログアウトすると管理画面に入れなくなる" do
    login_as_admin

    delete admin_logout_path
    assert_redirected_to admin_login_path
    assert_nil session[:current_admin_user_id]

    get admin_root_path
    assert_redirected_to admin_login_path
  end

  test "利用テナント側の画面は配信しない" do
    # appstdio_admin で接続しているため、利用テナント側を動かすとテナントの遮断が効かない
    get "/login"
    assert_response :not_found

    get "/select_tenant"
    assert_response :not_found
  end

  private

  def login_as_admin
    post admin_login_path, params: { email: @operator.email, password: PASSWORD }
  end
end
