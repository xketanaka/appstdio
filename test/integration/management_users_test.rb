require "test_helper"

class ManagementUsersTest < ActionDispatch::IntegrationTest
  PASSWORD = "password1234".freeze

  # 全社 > 営業部・開発部。佐藤さんは営業部（グループ管理者）と、停止中の旧企画部に所属
  setup do
    @tenant = Tenant.setup!(name: "テナントA")
    @admin = User.create!(email: "admin@example.com", password: PASSWORD)
    TenantContext.switch(tenant: @tenant) do
      @admin_member = TenantUser.create!(tenant: @tenant, user: @admin, display_name: "管理者さん", role: :admin, status: :active)
      @sato = TenantUser.create!(tenant: @tenant, user: User.create!(email: "sato@example.com", password: PASSWORD),
        display_name: "佐藤さん", role: :member, status: :active)

      @company = Group.create!(tenant: @tenant, name: "全社")
      @sales = Group.create!(tenant: @tenant, parent: @company, name: "営業部")
      @dev = Group.create!(tenant: @tenant, parent: @company, name: "開発部")
      @planning = Group.create!(tenant: @tenant, name: "旧企画部")
      GroupMember.create!(tenant: @tenant, group: @sales, tenant_user: @sato, role: :leader)
      GroupMember.create!(tenant: @tenant, group: @planning, tenant_user: @sato)
      @planning.suspend!(by: @admin_member)
    end
  end

  teardown do
    TenantContext.clear
  end

  test "一覧の名前から詳細を開くと、所属グループを最上位からの並びで出す" do
    login(@admin)
    get management_users_path
    assert_select "#user-list a[href=?]", management_user_path(@sato), text: "佐藤さん"

    get management_user_path(@sato)
    assert_response :success
    assert_select "#user-detail dd", text: "佐藤さん"
    assert_select "#user-detail dd", text: "sato@example.com"
    assert_select "#user-groups h3", text: "所属グループ（2件）"
    rows = css_select("#user-groups tr").map { it.text.squish }
    assert_equal ["営業部 グループ管理者 全社", "旧企画部 停止中"], rows
    assert_select "#user-groups a[href=?]", management_group_path(@sales)
  end

  test "所属グループが無ければその旨を出す" do
    login(@admin)
    get management_user_path(@admin_member)
    assert_select "#user-groups h3", text: "所属グループ（0件）"
    assert_select "#user-groups p", text: "所属しているグループはありません。"
  end

  test "削除済みの人は一覧に出さず、詳細も開けない" do
    TenantContext.switch(tenant: @tenant) { @sato.update!(status: :deleted) }
    login(@admin)

    get management_users_path
    assert_select "#user-list tbody tr", 1
    get management_user_path(@sato)
    assert_response :not_found
  end

  test "他のテナントの人の詳細は開けない" do
    other = Tenant.setup!(name: "テナントB")
    outsider = TenantContext.switch(tenant: other) do
      TenantUser.create!(tenant: other, user: User.create!(email: "b@example.com", password: PASSWORD),
        display_name: "Bさん", status: :active)
    end
    login(@admin)

    get management_user_path(outsider)
    assert_response :not_found
  end

  private

  def login(user)
    post login_path, params: { email: user.email, password: PASSWORD }
    follow_redirect!
    follow_redirect!
  end
end
