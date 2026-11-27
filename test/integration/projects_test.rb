require "test_helper"

class ProjectsTest < ActionDispatch::IntegrationTest
  PASSWORD = "password1234".freeze

  # プロジェクト機能を利用する。佐藤さんは「新製品開発」（プロジェクト管理者）と「社内改善」、
  # 利用停止中の「旧基盤」に参加。山田さんは「新製品開発」だけ。管理者さんはどれにも参加していない
  setup do
    @tenant = Tenant.setup!(name: "テナントA")
    in_tenant do
      TenantSetting.find_by!(tenant: @tenant).update!(projects_enabled: true)
      @admin = create_user("admin", "管理者さん", role: :admin)
      @sato = create_user("sato", "佐藤さん")
      @yamada = create_user("yamada", "山田さん")
      @product = create_project("新製品開発", labels: %w[社外], members: { @sato => :leader, @yamada => :member })
      @kaizen = create_project("社内改善", members: { @sato => :member })
      @legacy = create_project("旧基盤", members: { @sato => :member })
      @legacy.suspend!(by: @admin)
    end
  end

  teardown do
    TenantContext.clear
  end

  def in_tenant(&) = TenantContext.switch(tenant: @tenant, &)

  def create_user(account, name, role: :member)
    TenantUser.create!(tenant: @tenant, user: User.create!(email: "#{account}@example.com", password: PASSWORD),
      display_name: name, role:, status: :active)
  end

  def create_project(name, members:, labels: [])
    Project.build(tenant: @tenant).tap do |project|
      project.save_with(name:, label_names: labels)
      members.each { |user, role| GroupMember.create!(tenant: @tenant, group: project.group, tenant_user: user, role:) }
    end
  end

  def login(tenant_user)
    post login_path, params: { email: tenant_user.user.email, password: PASSWORD }
    follow_redirect!
    follow_redirect!
  end

  def switcher_entries
    css_select("#project-switcher li a").map(&:text)
  end

  test "メニューの「プロジェクト」から、参加している有効なプロジェクトの一覧を開く" do
    login(@sato)
    get top_page_path
    assert_select "dialog[data-drawer] nav a[href=?]", projects_path, text: "プロジェクト"

    get projects_path
    assert_equal ["社内改善 1人", "新製品開発 社外 佐藤さん 2人"],
      css_select("#project-list tbody tr").map { it.text.squish }
  end

  test "プロジェクトを開くと、ヘッダーにプロジェクト名、本文にラベルとメンバーを出す" do
    login(@sato)
    get project_path(@product)

    assert_response :success
    assert_select "#header-context a[href=?]", project_path(@product), text: "新製品開発"
    assert_select "#project-header h1", text: "新製品開発"
    assert_select "#project-labels li", text: "社外"
    assert_equal ["佐藤さん プロジェクト管理者", "山田さん"], css_select("#project-members tr").map { it.text.squish }
  end

  test "帯の切り替えメニューには、最近開いた順に、今も参加している有効なプロジェクトを出す" do
    login(@sato)
    get project_path(@kaizen)
    get project_path(@product)

    assert_equal ["新製品開発", "社内改善"], switcher_entries
    assert_select "#project-switcher a[aria-current=page]", text: "新製品開発"
    assert_select "#all-projects[href=?]", projects_path

    in_tenant { GroupMember.find_by!(group: @kaizen.group, tenant_user: @sato).destroy! }
    get project_path(@product)
    assert_equal ["新製品開発"], switcher_entries, "抜けたプロジェクトは出さない"
  end

  test "参加していないプロジェクトと、利用停止中のプロジェクトは開けない。テナントの管理者も同じ" do
    login(@yamada)
    get project_path(@kaizen)
    assert_response :not_found

    login(@sato)
    get project_path(@legacy)
    assert_response :not_found

    login(@admin)
    get project_path(@product)
    assert_response :not_found
    get projects_path
    assert_select "#project-list", 0
  end

  test "プロジェクト機能を利用しないにすると、メニューから消え、画面も開けない" do
    in_tenant { TenantSetting.find_by!(tenant: @tenant).update!(projects_enabled: false) }
    login(@sato)

    get top_page_path
    assert_select "dialog[data-drawer] nav", text: /プロジェクト/, count: 0
    get projects_path
    assert_response :not_found
    get project_path(@product)
    assert_response :not_found
  end
end
