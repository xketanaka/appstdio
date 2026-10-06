require "test_helper"

class ManagementTest < ActionDispatch::IntegrationTest
  PASSWORD = "password1234".freeze

  setup do
    @tenant = Tenant.setup!(name: "テナントA")
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

    [management_users_path, management_groups_path, management_tenants_path].each do |path|
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
      management_tenants_path => "組織管理" }.each do |path, label|
      get path
      assert_response :success
      assert_select "#side-pane a[aria-current=page]", text: label
      assert_select "#side-pane a[aria-current]", 1
      assert_select "h1", text: label
    end
  end

  test "組織管理には自分のテナントの情報を出す" do
    Tenant.setup!(name: "テナントB")
    login(@admin)
    get management_tenants_path

    assert_select "#tenant dd", text: "テナントA"
    assert_select "#tenant dd", text: @tenant.id
    assert_select "#tenant", text: /テナントB/, count: 0
  end

  test "グループ管理ではグループの階層をツリーで出す" do
    login(@admin)
    get management_groups_path
    assert_response :success

    assert_select "#group-tree #everyone-group a[href=?]", management_group_path(100), text: "全員"
    assert_select "#group-tree a[href=?]", management_group_path(2), text: "営業本部"
    assert_select "#group-tree details > summary a", text: "全社"
    assert_select "#group-tree details details > summary a", text: "営業本部"
    assert_select "#group-tree details details > div a", text: "第一営業部"
    assert_select "#group-detail", 0
  end

  test "グループを選ぶと詳細を出し、上位グループには自分と下位を選べない" do
    login(@admin)
    get management_group_path(2)
    assert_response :success

    assert_select "#group-tree a[aria-current=page]", text: "営業本部"
    assert_select "#group-detail" do
      assert_select "input[name=group_name][value=?]", "営業本部"
      assert_select "select[name=group_parent_id] option[selected]", text: "全社"
      assert_select "select[name=group_parent_id] option", text: /営業本部|第一営業部|第二営業部/, count: 0
      assert_select "select[name=group_parent_id] option", text: /開発部/
      assert_select "select[name=group_parent_id] option", text: "全員", count: 0

      assert_select "#direct-members tr", 2
      # 田中さんは第一・第二営業部の両方にいるが1行にまとめる
      assert_select "#sub-members tr", 4
      assert_select "#sub-members tr", text: /田中 三郎.*第一営業部.*第二営業部/m
      assert_select "p", text: /下位グループを含めて 6人/
    end
  end

  test "上位グループは階層をたどって表示する" do
    login(@admin)

    get management_group_path(3)
    assert_select "#group-parent summary", text: /全社\s*>\s*営業本部/

    get management_group_path(1)
    assert_select "#group-parent summary", text: /（なし）/
  end

  test "グループの追加は、選んでいるグループを上位の初期値にする" do
    login(@admin)

    get management_groups_path
    assert_select "#new-group[href=?]", new_management_group_path

    get management_group_path(2)
    assert_select "#new-group[href=?]", new_management_group_path(parent_id: 2)

    # 「全員」は親にしないので、選んでいても最上位に追加する
    get management_group_path(100)
    assert_select "#new-group[href=?]", new_management_group_path

    get new_management_group_path(parent_id: 3)
    assert_response :success
    assert_select "#group-form" do
      assert_select "input[name=group_name]:not([value])"
      assert_select "#group-parent summary", text: /全社\s*>\s*営業本部\s*>\s*第一営業部/
      assert_select "select[name=group_parent_id] option[selected]", text: /第一営業部/
    end

    get new_management_group_path
    assert_select "#group-parent summary", text: /（なし）/
  end

  test "「全員」グループは読み取り専用で、サブグループの欄を出さない" do
    login(@admin)
    get management_group_path(100)
    assert_response :success

    assert_select "#group-tree #everyone-group a[aria-current=page]", text: "全員"
    assert_select "#group-detail" do
      assert_select "input, select", 0
      assert_select "p", text: /自動でメンバーになります/
    end
    assert_select "#sub-members", 0
  end

  test "存在しないグループは 404" do
    login(@admin)
    get management_group_path(999)
    assert_response :not_found
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
