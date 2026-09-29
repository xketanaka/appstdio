require "test_helper"

class ManagementTest < ActionDispatch::IntegrationTest
  PASSWORD = "password1234".freeze

  setup do
    @tenant = Tenant.create!(name: "テナントA")
    @owner = User.create!(email: "owner@example.com", password: PASSWORD)
    @admin = User.create!(email: "admin@example.com", password: PASSWORD)
    @member = User.create!(email: "member@example.com", password: PASSWORD)
    TenantContext.switch(tenant: @tenant) do
      TenantUser.create!(tenant: @tenant, user: @owner, display_name: "オーナーさん", role: :owner, status: :active)
      TenantUser.create!(tenant: @tenant, user: @admin, display_name: "管理者さん", role: :admin, status: :active)
      TenantUser.create!(tenant: @tenant, user: @member, display_name: "メンバーさん", role: :member, status: :active)
    end
  end

  teardown do
    TenantContext.clear
  end

  test "管理者にはメニューに「管理」が出る" do
    [@owner, @admin].each do |user|
      login(user)
      get top_page_path
      assert_select "dialog[data-drawer] nav a[href=?]", management_root_path, text: "管理"
      delete logout_path
    end
  end

  test "一般の利用者にはメニューに「管理」を出さず、URL を直接開いても 404 にする" do
    login(@member)
    get top_page_path
    assert_select "dialog[data-drawer] nav a[href=?]", management_root_path, 0
    assert_select "dialog[data-drawer] nav", text: /管理/, count: 0

    [management_users_path, management_groups_path, management_organizations_path].each do |path|
      get path
      assert_response :not_found
    end
  end

  test "「管理」を開くと利用者管理が選ばれた状態の2ペインになる" do
    login(@owner)
    get management_root_path
    assert_redirected_to management_users_path
    follow_redirect!
    assert_response :success

    assert_select "#side-pane a", 3
    assert_select "#side-pane", text: /\A管理\s*利用者管理.*グループ管理.*組織管理/m
    assert_select "#side-pane a[aria-current=page]", text: "利用者管理"
    assert_select "h1", text: "利用者管理"

    assert_select "#user-list tbody tr", 3
    assert_select "#user-list tbody", text: /member@example\.com/
    assert_select "#user-list tbody", text: /メンバー/
  end

  test "左ペインでグループ管理・組織管理に切り替えられる" do
    login(@admin)
    { management_groups_path => "グループ管理",
      management_organizations_path => "組織管理" }.each do |path, label|
      get path
      assert_response :success
      assert_select "#side-pane a[aria-current=page]", text: label
      assert_select "#side-pane a[aria-current]", 1
      assert_select "h1", text: label
    end
  end

  test "組織管理には自分のテナントの情報を出す" do
    Tenant.create!(name: "テナントB")
    login(@admin)
    get management_organizations_path

    assert_select "#organization dd", text: "テナントA"
    assert_select "#organization dd", text: @tenant.id
    assert_select "#organization", text: /テナントB/, count: 0
  end

  test "未ログインでは開けない" do
    get management_users_path
    assert_redirected_to login_path
  end

  private

  def login(user)
    post login_path, params: { email: user.email, password: PASSWORD }
    follow_redirect!
    follow_redirect!
  end
end
