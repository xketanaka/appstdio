require "test_helper"

class ManagementGroupsTest < ActionDispatch::IntegrationTest
  PASSWORD = "password1234".freeze

  # 全社 > 営業本部 > 第一営業部・第二営業部、全社 > 開発本部 > 開発部。
  # 全社の下の旧企画部は利用停止中
  setup do
    @tenant = Tenant.setup!(name: "テナントA")
    @admin = User.create!(email: "admin@example.com", password: PASSWORD)
    TenantContext.switch(tenant: @tenant) do
      admin = TenantUser.create!(tenant: @tenant, user: @admin, display_name: "管理者さん", role: :admin, status: :active)
      people = { "佐藤" => "sato", "山田" => "yamada", "田中" => "tanaka", "鈴木" => "suzuki", "高橋" => "takahashi" }
        .to_h do |name, account|
        user = User.create!(email: "#{account}@example.com", password: PASSWORD)
        [name, TenantUser.create!(tenant: @tenant, user:, display_name: "#{name}さん", role: :member, status: :active)]
      end

      @everyone = Group.everyone_of(@tenant)
      @company = Group.create!(tenant: @tenant, name: "全社")
      @sales = Group.create!(tenant: @tenant, parent: @company, name: "営業本部")
      @sales1 = Group.create!(tenant: @tenant, parent: @sales, name: "第一営業部")
      @sales2 = Group.create!(tenant: @tenant, parent: @sales, name: "第二営業部")
      @dev_hq = Group.create!(tenant: @tenant, parent: @company, name: "開発本部")
      @dev = Group.create!(tenant: @tenant, parent: @dev_hq, name: "開発部")
      @planning = Group.create!(tenant: @tenant, parent: @company, name: "旧企画部")
      @planning.update!(suspended_at: Time.current, suspended_by: admin, suspended_path: ["全社"], suspension_root: @planning)

      GroupMember.create!(tenant: @tenant, group: @sales, tenant_user: people["山田"])
      GroupMember.create!(tenant: @tenant, group: @sales, tenant_user: people["佐藤"], role: :leader)
      GroupMember.create!(tenant: @tenant, group: @sales1, tenant_user: people["田中"])
      GroupMember.create!(tenant: @tenant, group: @sales1, tenant_user: people["鈴木"])
      GroupMember.create!(tenant: @tenant, group: @sales2, tenant_user: people["田中"])
      GroupMember.create!(tenant: @tenant, group: @sales2, tenant_user: people["高橋"])

      %w[営業 本部].each do |name|
        GroupLabeling.create!(tenant: @tenant, group: @sales, group_label: GroupLabel.find_or_create_by!(tenant: @tenant, name:))
      end
      GroupLabel.create!(tenant: @tenant, name: "プロジェクト")
    end
  end

  teardown do
    TenantContext.clear
  end

  test "グループの階層をツリーで出し、利用停止中のグループは出さない" do
    login(@admin)
    get management_groups_path
    assert_response :success

    assert_select "#group-tree #everyone-group a[href=?]", management_group_path(@everyone), text: "全員"
    assert_select "#group-tree a[href=?]", management_group_path(@sales), text: "営業本部"
    assert_select "#group-tree details > summary a", text: "全社"
    assert_select "#group-tree details details > summary a", text: "営業本部"
    assert_select "#group-tree details details > div a", text: "第一営業部"
    assert_select "#group-tree", text: /旧企画部/, count: 0
    assert_select "#group-detail", 0
  end

  test "グループを選ぶと詳細を参照だけで出し、編集ボタンを置く" do
    login(@admin)
    get management_group_path(@sales)
    assert_response :success

    assert_select "#group-tree a[aria-current=page]", text: "営業本部"
    assert_select "#edit-group[href=?]", edit_management_group_path(@sales)
    assert_select "#group-detail" do
      assert_select "input, select, button", 0
      assert_select "dd", text: "営業本部"
      assert_select "#direct-members tr", 2

      # 下位グループのメンバーは人数だけ出して閉じておき、一覧は開いたときに読み込む。
      # 田中さんは2つの部にいるが1人と数える
      assert_select "details#sub-members:not([open])" do
        assert_select "summary", text: "下位グループに所属するメンバー（3人）"
        assert_select "li[data-load-more=?]", sub_members_management_group_path(@sales, page: 1)
      end
    end

    get management_group_path(@dev)
    assert_select "#sub-members", 0
  end

  test "下位グループのメンバーを1ページずつ返し、続きがあれば次の読み込み先を付ける" do
    TenantContext.switch(tenant: @tenant) do
      31.times do |i|
        user = User.create!(email: "dev#{i}@example.com", password: PASSWORD)
        tenant_user = TenantUser.create!(tenant: @tenant, user:, display_name: format("開発%02d", i), role: :member, status: :active)
        GroupMember.create!(tenant: @tenant, group: @dev, tenant_user:)
      end
    end
    login(@admin)

    # 全社の下位は 36人（営業の5人と開発部の31人。田中さんは1人と数える）
    get sub_members_management_group_path(@company, page: 1)
    assert_response :success
    assert_not_includes response.body, "<html"
    assert_select "li:not([data-load-more])", 30
    assert_select "li[data-load-more=?]", sub_members_management_group_path(@company, page: 2)

    get sub_members_management_group_path(@company, page: 2)
    assert_select "li:not([data-load-more])", 6
    assert_select "li[data-load-more]", 0

    # 同じ人が複数の下位グループにいれば1行にまとめ、所属するグループを並べる
    get sub_members_management_group_path(@sales, page: 1)
    assert_select "li", 3
    assert_select "li", text: /田中さん.*第一営業部.*第二営業部/m

    get sub_members_management_group_path(@everyone, page: 1)
    assert_response :not_found
  end

  test "詳細ではラベルをチップで出し、グループ管理者を先頭に印を付けて並べる" do
    login(@admin)

    get management_group_path(@sales)
    assert_select "#group-labels span", 2
    assert_select "#group-labels", text: /営業\s*本部/
    assert_select "#direct-members tr:first-child", text: /佐藤さん\s*管理者/
    assert_select "#direct-members tr:last-child", text: /管理者/, count: 0

    get management_group_path(@company)
    assert_select "#group-labels", text: "（なし）"
    assert_select "#direct-members", text: /管理者/, count: 0
  end

  test "上位グループは階層をたどって表示する" do
    login(@admin)

    get management_group_path(@sales1)
    assert_select "#group-parent-path", text: /全社\s*>\s*営業本部/
    assert_select "#group-parent-path a[href=?]", management_group_path(@sales)

    get management_group_path(@company)
    assert_select "#group-parent-path", text: /（なし）/
  end

  test "編集の画面に今の値を出し、上位には自分と下位・「全員」・利用停止中を選べない" do
    login(@admin)
    get edit_management_group_path(@sales)
    assert_response :success

    assert_select "#group-tree a[aria-current=page]", text: "営業本部"
    assert_select "#group-form" do
      assert_select "input[name=group_name][value=?]", "営業本部"
      assert_select "#group-parent summary", text: /全社/
      assert_select "select[name=group_parent_id] option[selected]", text: "全社"
      assert_select "select[name=group_parent_id] option", text: /営業本部|第一営業部|第二営業部/, count: 0
      assert_select "select[name=group_parent_id] option", text: /開発部/
      assert_select "select[name=group_parent_id] option", text: /全員|旧企画部/, count: 0

      assert_select "label-input" do |elements|
        assert_includes JSON.parse(elements.first["data-suggestions"]), "プロジェクト"
        assert_select "input[name=group_labels][value=?]", "営業, 本部"
      end

      assert_select "#direct-members tr", 2
      assert_select "#direct-members tr:first-child input[type=checkbox][name='leaders[]'][checked]"
      assert_select "#direct-members tr:last-child input[type=checkbox][name='leaders[]']:not([checked])"
      assert_select "button", text: "保存する"
      assert_select "a[href=?]", management_group_path(@sales), text: "キャンセル"
    end
  end

  test "グループの追加は、ツリーの末尾・行ごと・詳細の画面の3か所から作る場所を決めて開く" do
    login(@admin)

    # ツリーの末尾は最上位に作る。どのグループを選んでいても同じ
    get management_groups_path
    assert_select "#new-group[href=?]", new_management_group_path
    get management_group_path(@sales)
    assert_select "#new-group[href=?]", new_management_group_path

    # ツリーの行ごとの「＋」は、その行のグループの下に作る。「全員」の行には無い
    assert_select "#group-tree a[aria-label=?][href=?]", "「第一営業部」の下にグループを追加",
      new_management_group_path(parent_id: @sales1)
    assert_select "#everyone-group a[aria-label]", 0

    # 詳細の画面からは、そのグループの下に作る
    assert_select "#add-child-group[href=?]", new_management_group_path(parent_id: @sales)
    get management_group_path(@everyone)
    assert_select "#add-child-group", 0

    get new_management_group_path(parent_id: @sales1)
    assert_response :success
    assert_select "#group-form" do
      assert_select "input[name=group_name]:not([value])"
      assert_select "#group-parent summary", text: /全社\s*>\s*営業本部\s*>\s*第一営業部/
      assert_select "select[name=group_parent_id] option[selected]", text: /第一営業部/
      assert_select "label-input input[name=group_labels][value='']"
    end

    get new_management_group_path
    assert_select "#group-parent summary", text: /（なし）/
  end

  test "「全員」グループは読み取り専用で、所属している人数を出す" do
    login(@admin)
    get management_group_path(@everyone)
    assert_response :success

    assert_select "#group-tree #everyone-group a[aria-current=page]", text: "全員"
    assert_select "#group-detail" do
      assert_select "input, select", 0
      assert_select "p", text: /全員（6人）が自動でメンバーになります/
    end
    assert_select "#sub-members", 0
    assert_select "#edit-group", 0

    get edit_management_group_path(@everyone)
    assert_response :not_found
  end

  test "他のテナントのグループと存在しないグループは 404" do
    other = Tenant.setup!(name: "テナントB")
    other_group = TenantContext.switch(tenant: other) { Group.create!(tenant: other, name: "よその部") }
    login(@admin)

    get management_group_path(other_group)
    assert_response :not_found
    get management_group_path(0)
    assert_response :not_found
  end

  private

  def login(user)
    post login_path, params: { email: user.email, password: PASSWORD }
    follow_redirect!
    follow_redirect!
  end
end
