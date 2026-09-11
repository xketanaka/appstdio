require "test_helper"

class LoginFlowTest < ActionDispatch::IntegrationTest
  PASSWORD = "password1234".freeze

  setup do
    @tenant = Tenant.create!(name: "テナントA")
    @other_tenant = Tenant.create!(name: "テナントB")
    @user = User.create!(email: "a@example.com", password: PASSWORD)
    @membership = join(@tenant, display_name: "Aさん", role: :owner)
  end

  teardown do
    TenantContext.clear
  end

  test "所属が1件ならテナント選択を挟まずにホームへ入る" do
    get top_page_path
    assert_redirected_to login_path

    post login_path, params: { email: @user.email, password: PASSWORD }
    assert_redirected_to select_tenant_path

    follow_redirect!
    assert_redirected_to top_page_path

    follow_redirect!
    assert_response :success
    assert_select ".detail dd", text: "Aさん"
  end

  test "所属が複数ならテナント選択画面が出る" do
    join(@other_tenant, display_name: "Bさん")

    post login_path, params: { email: @user.email, password: PASSWORD }
    follow_redirect!

    assert_response :success
    assert_select ".tenant-list__name", 2

    post select_tenant_path, params: { tenant_id: @other_tenant.id }
    assert_redirected_to top_page_path

    follow_redirect!
    assert_select ".detail dd", text: "Bさん"
  end

  test "選択済みなら所属が1件でも一覧を出す（切り替えの導線）" do
    login_and_select

    get select_tenant_path
    assert_response :success
    assert_select ".tenant-list__name", 1
  end

  test "テナントを選ぶまでは業務画面に入れない" do
    join(@other_tenant, display_name: "Bさん")
    post login_path, params: { email: @user.email, password: PASSWORD }

    get top_page_path
    assert_redirected_to select_tenant_path
  end

  test "管理画面は配信しない" do
    # 管理画面は ADMIN_CONSOLE=1 の別プロセスで動かす
    get "/admin"
    assert_response :not_found
  end

  test "パスワードが違うとログインできない" do
    post login_path, params: { email: @user.email, password: "wrong-password" }

    assert_response :unprocessable_entity
    assert_select ".alert", text: /メールアドレスまたはパスワードが違います/
    assert_nil session[:current_user_id]
  end

  test "存在しないメールアドレスでもパスワード誤りと同じ応答になる" do
    post login_path, params: { email: "nobody@example.com", password: PASSWORD }

    assert_response :unprocessable_entity
    assert_select ".alert", text: /メールアドレスまたはパスワードが違います/
  end

  test "メールアドレスの大文字小文字は区別されない" do
    post login_path, params: { email: "A@EXAMPLE.COM", password: PASSWORD }

    assert_redirected_to select_tenant_path
  end

  test "所属していないテナントには切り替えられない" do
    post login_path, params: { email: @user.email, password: PASSWORD }

    post select_tenant_path, params: { tenant_id: @other_tenant.id }
    assert_response :unprocessable_entity
    assert_nil session[:current_tenant_id]
  end

  test "所属が active でなければ選択肢に出ない" do
    TenantContext.switch(tenant: @tenant) { @membership.update!(status: :suspended) }

    post login_path, params: { email: @user.email, password: PASSWORD }
    follow_redirect!

    assert_response :success
    assert_select ".tenant-list__name", 0
    assert_select ".card__empty"
  end

  test "ログイン前に見ようとしたページへ戻る" do
    join(@other_tenant, display_name: "Bさん")

    get top_page_path
    assert_redirected_to login_path

    post login_path, params: { email: @user.email, password: PASSWORD }
    post select_tenant_path, params: { tenant_id: @tenant.id }
    assert_redirected_to top_page_path
  end

  test "ログアウトするとセッションが破棄される" do
    login_and_select
    assert_equal @user.id, session[:current_user_id]

    delete logout_path
    assert_redirected_to login_path
    assert_nil session[:current_user_id]
    assert_nil session[:current_tenant_id]

    get top_page_path
    assert_redirected_to login_path
  end

  test "ログイン時にセッションIDが再生成される" do
    get login_path
    session_before = session.id

    post login_path, params: { email: @user.email, password: PASSWORD }

    assert_not_equal session_before, session.id
  end

  test "last_signed_in_at が記録される" do
    assert_nil @user.last_signed_in_at

    post login_path, params: { email: @user.email, password: PASSWORD }

    assert_not_nil @user.reload.last_signed_in_at
  end

  private

  def join(tenant, display_name:, role: :member)
    TenantContext.switch(tenant: tenant) do
      TenantUser.create!(
        tenant: tenant, user: @user, display_name: display_name, role: role, status: :active,
      )
    end
  end

  # 所属1件なので、ログインすると自動でテナントが選択される
  def login_and_select
    post login_path, params: { email: @user.email, password: PASSWORD }
    follow_redirect!
    follow_redirect!
  end
end
