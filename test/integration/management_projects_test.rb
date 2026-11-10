require "test_helper"

class ManagementProjectsTest < ActionDispatch::IntegrationTest
  PASSWORD = "password1234".freeze

  # プロジェクト機能を利用する。プロジェクト「新製品開発」に佐藤さん（プロジェクト管理者）と山田さん。
  # 部署は営業部（佐藤さんが所属）
  setup do
    @tenant = Tenant.setup!(name: "テナントA")
    TenantContext.switch(tenant: @tenant) do
      TenantSetting.find_by!(tenant: @tenant).update!(projects_enabled: true)
      @admin = create_user("admin", "管理者さん", role: :admin)
      @sato = create_user("sato", "佐藤さん")
      @yamada = create_user("yamada", "山田さん")
      @sales = Group.create!(tenant: @tenant, name: "営業部")
      GroupMember.create!(tenant: @tenant, group: @sales, tenant_user: @sato)
      @project = Project.build(tenant: @tenant).tap { it.save_with(name: "新製品開発", label_names: %w[社外]) }
      GroupMember.create!(tenant: @tenant, group: @project.group, tenant_user: @sato, role: :leader)
      GroupMember.create!(tenant: @tenant, group: @project.group, tenant_user: @yamada)
    end
  end

  teardown do
    TenantContext.clear
  end

  def create_user(account, name, role: :member)
    TenantUser.create!(tenant: @tenant, user: User.create!(email: "#{account}@example.com", password: PASSWORD),
      display_name: name, role:, status: :active)
  end

  def in_tenant(&) = TenantContext.switch(tenant: @tenant, &)

  test "一覧にプロジェクト名・ラベル・プロジェクト管理者・人数を出し、詳細でメンバーを出す" do
    login(@admin)
    get management_projects_path

    assert_select "#side-pane a[aria-current=page]", text: "プロジェクト管理"
    row = css_select("#project-list tbody tr").first.text.squish
    assert_equal "新製品開発 社外 佐藤さん 2人", row

    get management_project_path(@project)
    assert_select "#project-header h2", text: "新製品開発"
    assert_select "#project-labels li", text: "社外"
    assert_equal ["佐藤さん プロジェクト管理者 sato@example.com", "山田さん yamada@example.com"],
      css_select("#project-members tr").map { it.text.squish }
  end

  test "作ると「プロジェクト」の下にグループができ、続けてメンバーの編集に移る" do
    login(@admin)
    post management_projects_path, params: { project: { name: "社内改善", label_names: "社内" } }

    project = in_tenant { Project.joins(:group).find_by!(groups: { name: "社内改善" }) }
    assert_redirected_to edit_members_management_project_path(project)
    in_tenant do
      assert project.group.parent.project_root?
      assert_equal %w[社内], project.labels.pluck(:name)
    end

    follow_redirect!
    assert_select "#members-form button#add-members"
  end

  test "名前が重なると作れず、誤りをプロジェクト名として出す" do
    login(@admin)
    post management_projects_path, params: { project: { name: "新製品開発", label_names: "" } }

    assert_response :unprocessable_entity
    assert_select "[role=alert]", text: /プロジェクト名が他のプロジェクトと重複しています/
  end

  test "名前とラベルを変えると、グループにも反映する" do
    login(@admin)
    patch management_project_path(@project), params: { project: { name: "新製品開発2", label_names: "社内" } }

    assert_redirected_to management_project_path(@project)
    in_tenant do
      assert_equal "新製品開発2", @project.group.reload.name
      assert_equal %w[社内], @project.labels.pluck(:name)
    end
  end

  test "メンバーを編集すると、グループのメンバーとして保存する" do
    login(@admin)
    get edit_members_management_project_path(@project)
    assert_select "pick-list[data-candidates-url=?]", member_candidates_management_group_path(@project.group)

    patch update_members_management_project_path(@project), params: { group: { members: { @yamada.id => "leader" } } }

    assert_redirected_to management_project_path(@project)
    in_tenant do
      assert_equal({ @yamada.id => "leader" }, @project.group.group_members.pluck(:tenant_user_id, :role).to_h)
    end
  end

  test "利用停止するとグループも止まり、停止中の一覧から開いて再開できる" do
    login(@admin)
    post suspend_management_project_path(@project)
    assert_redirected_to management_project_path(@project)
    assert in_tenant { @project.group.reload.suspended? }

    get management_projects_path
    assert_select "#project-list", 0
    get suspended_management_projects_path
    assert_select "#suspended-projects a[href=?]", management_project_path(@project), text: "新製品開発"

    get management_project_path(@project)
    assert_select "#suspension"
    assert_select "#edit-project", 0
    get edit_management_project_path(@project)
    assert_response :not_found

    post reactivate_management_project_path(@project)
    assert_not in_tenant { @project.group.reload.suspended? }
  end

  test "削除するとグループも消える" do
    login(@admin)
    get confirm_destroy_management_project_path(@project)
    assert_select "#destroy-confirmation", text: /新製品開発/

    delete management_project_path(@project)

    assert_redirected_to management_projects_path
    in_tenant do
      assert_not Project.exists?(@project.id)
      assert_not Group.exists?(@project.group_id)
    end
  end

  test "プロジェクト機能を利用しないなら開けず、メニューにも出さない" do
    in_tenant { TenantSetting.find_by!(tenant: @tenant).update!(projects_enabled: false) }
    login(@admin)

    get management_projects_path
    assert_response :not_found
    get management_users_path
    assert_select "#side-pane", text: /プロジェクト管理/, count: 0
  end

  test "メンバーはプロジェクト管理を開けない" do
    login(@sato)

    get management_projects_path

    assert_response :not_found
  end

  test "グループ管理では、部署の後ろの「プロジェクト」の下にプロジェクトのグループを出す" do
    login(@admin)
    get management_groups_path

    root = in_tenant { Group.project_root.first }
    assert_select "#group-tree #project-groups summary a[href=?]", management_group_path(root), text: "プロジェクト"
    assert_select "#group-tree #project-groups a[href=?]", management_group_path(@project.group), text: "新製品開発"
    # 上位グループの候補には出さない
    get new_management_group_path
    assert_select "select#group_parent_id option", text: /プロジェクト|新製品開発/, count: 0
  end

  test "「プロジェクト」は編集・削除・メンバーの編集ができない" do
    root = in_tenant { Group.project_root.first }
    login(@admin)

    get management_group_path(root)
    assert_response :success
    assert_select "#group-actions", 0
    [edit_management_group_path(root), edit_members_management_group_path(root), confirm_destroy_management_group_path(root),
     confirm_suspend_management_group_path(root)].each do |path|
      get path
      assert_response :not_found
    end
  end

  test "プロジェクトのグループは、グループ管理ではラベルとメンバーだけを編集でき、削除・利用停止・下位グループの追加はできない" do
    group = @project.group
    login(@admin)

    get management_group_path(group)
    assert_select "#group-actions a", text: "ラベルを編集"
    assert_select "#group-actions a", text: "メンバーを編集"
    assert_select "#add-child-group", 0
    assert_select "#project-note"

    get edit_management_group_path(group)
    assert_select "#group-form input[name=?]", "group[name]", 0
    assert_select "#group-parent", 0
    assert_select "#suspend-group", 0
    assert_select "#destroy-group", 0

    # 名前や上位を送っても変えない
    patch management_group_path(group), params: { group: { name: "別の名前", parent_id: @sales.id, label_names: "社内" } }
    assert_redirected_to management_group_path(group)
    in_tenant do
      group.reload
      assert_equal "新製品開発", group.name
      assert group.parent.project_root?
      assert_equal %w[社内], group.labels.pluck(:name)
    end

    [confirm_destroy_management_group_path(group), confirm_suspend_management_group_path(group)].each do |path|
      get path
      assert_response :not_found
    end
    post suspend_management_group_path(group)
    assert_response :not_found
    post management_groups_path, params: { group: { name: "チーム", parent_id: group.id } }
    assert_response :unprocessable_entity
  end

  test "停止中のプロジェクトのグループは、グループ管理から再開できない" do
    in_tenant { @project.suspend!(by: @admin) }
    login(@admin)

    get management_group_path(@project.group)
    assert_select "#suspension", text: /再開はプロジェクト管理で/
    assert_select "#suspension button", 0
    post reactivate_management_group_path(@project.group)
    assert_response :not_found
  end

  test "プロジェクト管理者は、グループ管理で自分のプロジェクトのメンバーを編集できる" do
    login(@sato)
    get management_groups_path

    assert_select "#group-tree #project-groups a[href=?]", management_group_path(@project.group)
    get edit_members_management_group_path(@project.group)
    assert_response :success
  end

  test "利用者の詳細では、参加プロジェクトを所属グループと分けて出す" do
    login(@admin)
    get management_user_path(@sato)

    assert_equal ["営業部"], css_select("#user-groups tr").map { it.text.squish }
    assert_select "#user-projects h3", text: "参加プロジェクト（1件）"
    assert_select "#user-projects a[href=?]", management_project_path(@project), text: "新製品開発"
    assert_select "#user-projects tr", text: /プロジェクト管理者/
  end

  test "利用者の編集では、参加プロジェクトも変えられ、プロジェクト機能を利用しないなら欄を出さず所属も残す" do
    other = in_tenant { Project.build(tenant: @tenant).tap { it.save_with(name: "社内改善", label_names: []) } }
    login(@admin)

    get edit_management_user_path(@yamada)
    assert_select "#user-projects tbody tr[data-row=?]", @project.group_id.to_s
    assert_select "pick-list[data-candidates-url=?]", group_candidates_management_users_path(kind: "project")

    get group_candidates_management_users_path(kind: "project")
    assert_equal %w[新製品開発 社内改善].sort, css_select("input[type=checkbox]").map { it["data-name"] }.sort
    get group_candidates_management_users_path
    assert_select "input[type=checkbox][data-name=?]", "新製品開発", 0

    patch management_user_path(@yamada), params: { tenant_user: { display_name: "山田さん", role: "member",
      group_ids: ["", @sales.id, other.group_id] } }
    assert_redirected_to management_user_path(@yamada)
    in_tenant { assert_equal [@sales.id, other.group_id].sort, @yamada.group_members.pluck(:group_id).sort }

    in_tenant { TenantSetting.find_by!(tenant: @tenant).update!(projects_enabled: false) }
    get edit_management_user_path(@yamada)
    assert_select "#user-projects", 0
    patch management_user_path(@yamada), params: { tenant_user: { display_name: "山田さん", role: "member", group_ids: [""] } }
    in_tenant { assert_equal [other.group_id], @yamada.group_members.pluck(:group_id) }
    get group_candidates_management_users_path(kind: "project")
    assert_response :not_found
  end

  test "共有の相手の候補にプロジェクトのグループを出し、「プロジェクト」は出さない" do
    login(@admin)

    get files_api_share_candidates_path, params: { q: "プロジェクト" }
    assert_empty response.parsed_body["candidates"].select { it["type"] == "group" }
    get files_api_share_candidates_path, params: { q: "新製品" }
    assert_equal [%w[プロジェクト 新製品開発]], response.parsed_body["candidates"].map { it["path"] }
  end

  private

  def login(tenant_user)
    post login_path, params: { email: tenant_user.user.email, password: PASSWORD }
    follow_redirect!
    follow_redirect!
  end
end
