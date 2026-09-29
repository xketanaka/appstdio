require "test_helper"

# 通常の bin/rails test では動かない。bin/rails test:ops で実行する
class OpsConsoleTest < ActionDispatch::IntegrationTest
  PASSWORD = "password1234".freeze

  setup do
    unless Rails.configuration.x.ops_console
      skip("管理画面のテストは bin/rails test:ops で実行する")
    end

    @tenant_a = Tenant.create!(name: "テナントA")
    @tenant_b = Tenant.create!(name: "テナントB")

    @operator = Operator.create!(
      email: "operator@example.com", password: PASSWORD, display_name: "運用担当", status: :active,
    )

    @tenant_member = User.create!(email: "member@example.com", password: PASSWORD)
    TenantUser.create!(
      tenant: @tenant_a, user: @tenant_member, display_name: "Aさん", status: :active,
    )
  end

  test "管理者としてログインしテナント一覧を見る" do
    get ops_root_path
    assert_redirected_to ops_login_path

    post ops_login_path, params: { email: @operator.email, password: PASSWORD }
    assert_redirected_to ops_root_path

    follow_redirect!
    assert_response :success
    assert_select "#tenant-table tbody tr", 2
    assert_select "td", text: "テナントA"
    assert_select "td", text: "テナントB"
  end

  test "所属ユーザ数はテナントを跨いで数えられる" do
    login_as_operator
    get ops_root_path

    assert_select "#tenant-table tbody tr:first-child td:nth-child(3)", text: "1"
    assert_select "#tenant-table tbody tr:last-child td:nth-child(3)", text: "0"
  end

  test "テナントコンテキストを設定しなくても所属情報が見える" do
    assert_nil TenantContext.tenant_id
    assert_equal 1, TenantUser.count
  end

  test "利用者のアカウントでは正しいパスワードでも入れない" do
    post ops_login_path, params: { email: @tenant_member.email, password: PASSWORD }

    assert_response :unprocessable_entity
    assert_select "[role=alert]", text: /メールアドレスまたはパスワードが違います/
    assert_nil session[:current_operator_id]
  end

  test "同じメールアドレスの利用者がいても、システム管理者のパスワードでしか入れない" do
    User.create!(email: @operator.email, password: "user-password")

    post ops_login_path, params: { email: @operator.email, password: "user-password" }
    assert_response :unprocessable_entity

    post ops_login_path, params: { email: @operator.email, password: PASSWORD }
    assert_redirected_to ops_root_path
  end

  test "停止中のシステム管理者はログインできない" do
    @operator.update!(status: :suspended)

    post ops_login_path, params: { email: @operator.email, password: PASSWORD }
    assert_response :unprocessable_entity
    assert_nil session[:current_operator_id]
  end

  test "ログイン前に見ようとしたページへ戻る" do
    get ops_tenants_path
    assert_redirected_to ops_login_path

    post ops_login_path, params: { email: @operator.email, password: PASSWORD }
    assert_redirected_to ops_tenants_path
  end

  test "ログアウトすると管理画面に入れなくなる" do
    login_as_operator

    delete ops_logout_path
    assert_redirected_to ops_login_path
    assert_nil session[:current_operator_id]

    get ops_root_path
    assert_redirected_to ops_login_path
  end

  test "メニューからテナント一覧へ行ける" do
    login_as_operator
    get ops_root_path

    assert_select "button[data-drawer-open]"
    assert_select "dialog[data-drawer]" do
      assert_select "a[href=?]", ops_tenants_path
      assert_select "span[aria-disabled=true]", 1
    end
  end

  test "ログイン前の画面にはメニューを出さない" do
    get ops_login_path

    assert_response :success
    assert_select "button[data-drawer-open]", 0
    assert_select "dialog[data-drawer]", 0
  end

  test "利用テナント側の画面は配信しない" do
    get "/login"
    assert_response :not_found

    get "/select_tenant"
    assert_response :not_found
  end

  private

  def login_as_operator
    post ops_login_path, params: { email: @operator.email, password: PASSWORD }
  end
end
