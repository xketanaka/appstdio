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

  test "一覧の名前から詳細を開くと、有効な所属グループを最上位からの並びで出す" do
    login(@admin)
    get management_users_path
    assert_select "#user-list a[href=?]", management_user_path(@sato), text: "佐藤さん"

    get management_user_path(@sato)
    assert_response :success
    assert_select "#user-detail dd", text: "佐藤さん"
    assert_select "#user-detail dd", text: "sato@example.com"
    # 停止中の旧企画部は出さない
    assert_select "#user-groups h3", text: "所属グループ（1件）"
    rows = css_select("#user-groups tr").map { it.text.squish }
    assert_equal ["営業部 グループ管理者 全社"], rows
    assert_select "#user-groups a[href=?]", management_group_path(@sales)
  end

  test "所属グループが無ければその旨を出す" do
    login(@admin)
    get management_user_path(@admin_member)
    assert_select "#user-groups h3", text: "所属グループ（0件）"
    assert_select "#user-groups p", text: "所属しているグループはありません。"
  end

  test "利用者を追加すると招待中で登録し、選んだグループに入れて詳細へ進む" do
    login(@admin)
    get management_users_path
    assert_select "a#new-user[href=?]", new_management_user_path

    get new_management_user_path
    assert_response :success
    # 停止中のグループと「全員」は選べない。グループ名の下に上位の並びを出す
    assert_equal ["全社", "営業部 全社", "開発部 全社"], css_select("#group-choices li").map { it.text.squish }
    assert_select "#user-form input[type=radio][name=?]", "tenant_user[role]", 2
    assert_select "#user-form input[type=radio][value=member][checked]"

    post management_users_path, params: { tenant_user: {
      email: "new@example.com", display_name: "新人さん", role: "member", group_ids: ["", @sales.id, @dev.id],
    } }
    tenant_user = TenantContext.switch(tenant: @tenant) { TenantUser.find_by!(display_name: "新人さん") }
    assert_redirected_to management_user_path(tenant_user)
    follow_redirect!
    assert_select "#user-detail dd", text: "招待中"
    assert_equal ["営業部 全社", "開発部 全社"], css_select("#user-groups tr").map { it.text.squish }
  end

  test "追加できなければ、入力したとおりに出し直す" do
    login(@admin)
    post management_users_path, params: { tenant_user: {
      email: "sato@example.com", display_name: "別の佐藤さん", role: "admin", group_ids: ["", @dev.id],
    } }

    assert_response :unprocessable_entity
    assert_select "[role=alert]", text: /メールアドレスの利用者はすでに登録されています。/
    assert_select "#user-form input[name=?][value=?]", "tenant_user[email]", "sato@example.com"
    assert_select "#user-form input[name=?][value=?]", "tenant_user[display_name]", "別の佐藤さん"
    assert_select "#user-form input[type=radio][value=admin][checked]"
    assert_select "#group-choices input[checked][value=?]", @dev.id.to_s
    assert_select "#group-choices input[checked]", 1
  end

  test "オーナーの権限では追加できない" do
    login(@admin)
    post management_users_path, params: { tenant_user: { email: "new@example.com", display_name: "新人さん", role: "owner" } }
    assert_response :not_found
  end

  test "詳細から確認の画面を経て削除すると、一覧から消え、テナントにも入れなくなる" do
    login(@admin)
    get management_user_path(@sato)
    assert_select "a#destroy-user[href=?]", confirm_destroy_management_user_path(@sato)

    get confirm_destroy_management_user_path(@sato)
    assert_response :success
    assert_select "#destroy-confirmation", text: /「佐藤さん」（sato@example.com）を削除します。/
    assert_select "form[action=?] button", management_user_path(@sato), text: "削除する"

    delete management_user_path(@sato)
    assert_redirected_to management_users_path
    follow_redirect!
    assert_select "#user-list", text: /佐藤さん/, count: 0
    assert_equal 0, TenantContext.switch(tenant: @tenant) { GroupMember.where(tenant_user: @sato).count }

    delete logout_path
    post login_path, params: { email: "sato@example.com", password: PASSWORD }
    follow_redirect!
    assert_select "form[action=?]", select_tenant_path, 0
  end

  test "オーナーと自分自身は削除できない" do
    owner = TenantContext.switch(tenant: @tenant) do
      TenantUser.create!(tenant: @tenant, user: User.create!(email: "owner@example.com", password: PASSWORD),
        display_name: "オーナーさん", role: :owner, status: :active)
    end
    login(@admin)

    [owner, @admin_member].each do |tenant_user|
      get management_user_path(tenant_user)
      assert_select "#destroy-user", 0
      get confirm_destroy_management_user_path(tenant_user)
      assert_response :not_found
      delete management_user_path(tenant_user)
      assert_response :not_found
    end
    assert TenantContext.switch(tenant: @tenant) { owner.reload.active? }
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
