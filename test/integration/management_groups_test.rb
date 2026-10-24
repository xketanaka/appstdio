require "test_helper"

class ManagementGroupsTest < ActionDispatch::IntegrationTest
  PASSWORD = "password1234".freeze

  # 全社 > 営業本部 > 第一営業部・第二営業部、全社 > 開発本部 > 開発部。
  # 全社の下の旧企画部は利用停止中
  setup do
    @tenant = Tenant.setup!(name: "テナントA")
    @admin = User.create!(email: "admin@example.com", password: PASSWORD)
    TenantContext.switch(tenant: @tenant) do
      @admin_member = admin = TenantUser.create!(tenant: @tenant, user: @admin, display_name: "管理者さん", role: :admin, status: :active)
      @people = people = { "佐藤" => "sato", "山田" => "yamada", "田中" => "tanaka", "鈴木" => "suzuki", "高橋" => "takahashi" }
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

  test "停止中の下位のメンバーは、有効なグループの「下位グループに所属するメンバー」に出さない" do
    TenantContext.switch(tenant: @tenant) { @sales2.suspend!(by: @admin_member) }
    login(@admin)

    get management_group_path(@sales)
    assert_select "#sub-members summary", text: "下位グループに所属するメンバー（2人）"
    get sub_members_management_group_path(@sales, page: 1)
    assert_select "li", 2
    assert_select "li", text: /第二営業部|高橋さん/, count: 0

    # 下位が停止中だけになったら欄ごと出さない
    TenantContext.switch(tenant: @tenant) { @sales1.suspend!(by: @admin_member) }
    get management_group_path(@sales)
    assert_select "#sub-members", 0

    # 停止中のグループの詳細は、一緒に止まった下位も含めて停止した時の形で出す
    TenantContext.switch(tenant: @tenant) { [@sales1, @sales2].each { it.reload.reactivate } }
    TenantContext.switch(tenant: @tenant) { @sales.suspend!(by: @admin_member) }
    get management_group_path(@sales)
    assert_select "#sub-members summary", text: "下位グループに所属するメンバー（3人）"
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
      assert_select "input[name=?][value=?]", "group[name]", "営業本部"
      assert_select "#group-parent summary", text: /全社/
      assert_select "select#group_parent_id option[selected]", text: "全社"
      assert_select "select#group_parent_id option", text: /営業本部|第一営業部|第二営業部/, count: 0
      assert_select "select#group_parent_id option", text: /開発部/
      assert_select "select#group_parent_id option", text: /全員|旧企画部/, count: 0

      assert_select "label-input" do |elements|
        assert_includes JSON.parse(elements.first["data-suggestions"]), "プロジェクト"
        assert_select "input#group_label_names[value=?]", "営業, 本部"
      end

      assert_select "#direct-members tbody tr", 2
      assert_select "#direct-members tbody tr:first-child", text: /佐藤さん/
      assert_select "#direct-members tbody tr:first-child input[type=checkbox][name=?][value=leader][checked]",
        "group[members][#{@people["佐藤"].id}]"
      assert_select "#direct-members tbody tr:last-child input[type=checkbox][value=leader]:not([checked])"
      assert_select "#add-members"
      assert_select "dialog#member-dialog"
      assert_select "input[type=submit][value=?]", "保存する"
      assert_select "a[href=?]", management_group_path(@sales), text: "キャンセル"
    end
  end

  test "グループを作ると、詳細の画面に移る。一覧に無いラベルはテナントのラベルに加わる" do
    login(@admin)
    post management_groups_path, params: { group: { name: " 第三営業部 ", parent_id: @sales.id, label_names: "営業、新設 ,営業" } }

    group = TenantContext.switch(tenant: @tenant) { Group.find_by!(name: "第三営業部") }
    assert_redirected_to management_group_path(group)
    follow_redirect!
    assert_select "[role=status]", text: "登録しました。"
    assert_select "#group-parent-path", text: /全社\s*>\s*営業本部/
    assert_select "#group-labels span", text: /\A(営業|新設)\z/, count: 2
    TenantContext.switch(tenant: @tenant) { assert GroupLabel.exists?(name: "新設") }
  end

  test "グループの名前・上位・ラベルを変える" do
    login(@admin)
    patch management_group_path(@sales1), params: { group: { name: "法人営業部", parent_id: @dev_hq.id, label_names: "本部" } }
    assert_redirected_to management_group_path(@sales1)

    TenantContext.switch(tenant: @tenant) do
      @sales1.reload
      assert_equal "法人営業部", @sales1.name
      assert_equal @dev_hq, @sales1.parent
      assert_equal ["本部"], @sales1.labels.pluck(:name)
    end

    # 最上位にもできる。ラベルを空にすると外れる
    patch management_group_path(@sales1), params: { group: { name: "法人営業部", parent_id: "", label_names: "" } }
    TenantContext.switch(tenant: @tenant) do
      assert_nil @sales1.reload.parent
      assert_empty @sales1.labels
    end
  end

  test "同じ上位の下に同じ名前の有効なグループがあると保存できず、入力を残して出し直す" do
    login(@admin)
    patch management_group_path(@sales1), params: { group: { name: "第二営業部", parent_id: @sales.id, label_names: "新しいラベル" } }
    assert_response :unprocessable_entity
    assert_select "[role=alert]", text: /グループ名が同じ上位グループの中のものと重複しています/
    assert_select "input#group_name[value=?]", "第二営業部"
    assert_select "input#group_label_names[value=?]", "新しいラベル"
    TenantContext.switch(tenant: @tenant) { assert_not GroupLabel.exists?(name: "新しいラベル") }

    # 停止中のグループとは重なってよい
    patch management_group_path(@sales1), params: { group: { name: "旧企画部", parent_id: @company.id, label_names: "" } }
    assert_redirected_to management_group_path(@sales1)
  end

  test "上位に自分の下位・「全員」・利用停止中のグループを指定すると保存できない" do
    login(@admin)
    [@sales1, @everyone, @planning].each do |parent|
      patch management_group_path(@sales), params: { group: { name: "営業本部", parent_id: parent.id, label_names: "" } }
      assert_response :unprocessable_entity
      assert_select "[role=alert]", text: /上位グループには/
    end

    post management_groups_path, params: { group: { name: "新しい部", parent_id: @planning.id, label_names: "" } }
    assert_response :unprocessable_entity
  end

  test "長すぎるラベルはグループの誤りとして出し、何も保存しない" do
    login(@admin)
    post management_groups_path, params: { group: { name: "新しい部", parent_id: "", label_names: "あ" * 101 } }
    assert_response :unprocessable_entity
    assert_select "[role=alert]", text: /ラベルは100文字以内/
    TenantContext.switch(tenant: @tenant) { assert_not Group.exists?(name: "新しい部") }
  end

  test "「全員」グループは変えられない" do
    login(@admin)
    patch management_group_path(@everyone), params: { group: { name: "みんな", parent_id: "", label_names: "" } }
    assert_response :not_found
  end

  test "メンバーを外す・足す・グループ管理者を切り替えるを、まとめて保存する" do
    login(@admin)
    patch management_group_path(@sales), params: { group: {
      name: "営業本部", parent_id: @company.id, label_names: "",
      members: { @people["山田"].id => "leader", @people["高橋"].id => "member" },
    } }
    assert_redirected_to management_group_path(@sales)

    roles = TenantContext.switch(tenant: @tenant) do
      @sales.group_members.includes(:tenant_user).to_h { [it.tenant_user.display_name, it.role] }
    end
    assert_equal({ "山田さん" => "leader", "高橋さん" => "member" }, roles)

    # 行をすべて外すと members は送られてこない
    patch management_group_path(@sales), params: { group: { name: "営業本部", parent_id: @company.id, label_names: "" } }
    TenantContext.switch(tenant: @tenant) { assert_empty @sales.group_members }
  end

  test "保存できなかったときは、送ったメンバーのとおりに出し直す" do
    login(@admin)
    patch management_group_path(@sales), params: { group: {
      name: "", parent_id: @company.id, label_names: "", members: { @people["高橋"].id => "leader" },
    } }
    assert_response :unprocessable_entity
    assert_select "#direct-members tbody tr", 1
    assert_select "#direct-members tbody tr", text: /高橋さん/
    assert_select "#direct-members tbody tr input[type=checkbox][value=leader][checked]"
    TenantContext.switch(tenant: @tenant) { assert_equal 2, @sales.group_members.count }
  end

  test "停止中の人と他のテナントの人はメンバーに足せない" do
    other = Tenant.setup!(name: "テナントB")
    stranger = TenantContext.switch(tenant: other) do
      TenantUser.create!(tenant: other, user: User.create!(email: "stranger@example.com", password: PASSWORD),
        display_name: "よその人", role: :member, status: :active)
    end
    TenantContext.switch(tenant: @tenant) { @people["高橋"].update!(status: :suspended) }
    login(@admin)

    [@people["高橋"], stranger].each do |tenant_user|
      patch management_group_path(@sales1), params: { group: {
        name: "第一営業部", parent_id: @sales.id, label_names: "", members: { tenant_user.id => "member" },
      } }
      assert_response :not_found
    end
    TenantContext.switch(tenant: @tenant) { assert_equal 2, @sales1.group_members.count }
  end

  test "メンバーの追加の候補は有効・招待中の人で、名前かメールアドレスで探せる" do
    TenantContext.switch(tenant: @tenant) do
      @people["鈴木"].update!(status: :invited)
      @people["高橋"].update!(status: :suspended)
    end
    login(@admin)

    get member_candidates_management_group_path(@sales)
    assert_response :success
    assert_not_includes response.body, "<html"
    # 管理者さんと、高橋さんを除く4人
    assert_select "li input[type=checkbox]", 5
    assert_select "li", text: /鈴木さん.*招待中/m
    assert_select "li", text: /高橋さん/, count: 0

    get member_candidates_management_group_path(@sales, q: "yamada")
    assert_select "li input[type=checkbox][value=?][data-name=?]", @people["山田"].id.to_s, "山田さん"
    assert_select "li input[type=checkbox]", 1

    get member_candidates_management_group_path(@sales, q: "佐藤")
    assert_select "li input[type=checkbox]", 1

    # LIKE の記号はそのままの文字として探す
    get member_candidates_management_group_path(@sales, q: "%")
    assert_select "li input[type=checkbox]", 0
    assert_select "li", text: "見つかりませんでした。"
  end

  test "メンバーの追加の候補は30人ずつ返し、続きは検索の条件を付けて読み足す" do
    TenantContext.switch(tenant: @tenant) do
      30.times do |i|
        user = User.create!(email: "dev#{i}@example.com", password: PASSWORD)
        TenantUser.create!(tenant: @tenant, user:, display_name: format("開発%02d", i), role: :member, status: :active)
      end
    end
    login(@admin)

    get member_candidates_management_group_path(@sales, q: "dev")
    assert_select "li input[type=checkbox]", 30
    assert_select "li[data-load-more=?]", member_candidates_management_group_path(@sales, q: "dev", page: 2), count: 0
    get member_candidates_management_group_path(@sales, q: "example")
    assert_select "li[data-load-more=?]", member_candidates_management_group_path(@sales, q: "example", page: 2)
    get member_candidates_management_group_path(@sales, q: "example", page: 2)
    assert_select "li input[type=checkbox]", 6
    assert_select "li", text: "見つかりませんでした。", count: 0
  end

  test "削除の確認で、一緒に消える下位の数とファイルの共有設定が消えることを示す" do
    login(@admin)
    get edit_management_group_path(@sales)
    assert_select "#destroy-group[href=?]", confirm_destroy_management_group_path(@sales)

    get confirm_destroy_management_group_path(@sales)
    assert_response :success
    assert_select "#destroy-confirmation", text: /「営業本部」を削除します。/
    assert_select "#destroy-confirmation", text: /下位グループ 2件も一緒に削除されます。/
    assert_select "#files-warning"
    assert_select "form[action=?] button", management_group_path(@sales), text: "削除する"

    # 下位が無ければ数を出さない。ファイル管理を使っていなければ共有設定の注意を出さない
    TenantContext.switch(tenant: @tenant) { Files::Setting.find_by!(tenant: @tenant).update!(enabled: false) }
    get confirm_destroy_management_group_path(@sales1)
    assert_select "#destroy-confirmation", text: /下位グループ/, count: 0
    assert_select "#files-warning", 0
  end

  test "削除すると、停止中も含めて下位とメンバー・ファイルの共有設定ごと消え、上位の詳細に戻る" do
    TenantContext.switch(tenant: @tenant) do
      @planning.update_columns(parent_id: @sales1.id)
      folder = Files::Node.create_folder!(parent: Files::Drive.shared_root(@tenant), name: "営業資料", creator: @people["佐藤"])
      @permission = Files::Permission.create!(tenant: @tenant, node: folder, group: @sales1, role: :none)
    end
    login(@admin)

    delete management_group_path(@sales)
    assert_redirected_to management_group_path(@company)
    follow_redirect!
    assert_select "[role=status]", text: "削除しました。"

    TenantContext.switch(tenant: @tenant) do
      assert_equal %w[全員 全社 開発本部 開発部], Group.order(:id).pluck(:name)
      assert_empty GroupMember.where(tenant_user: @people["田中"])
      assert_not Files::Permission.exists?(@permission.id)
      # ラベルはテナントの一覧に残る
      assert GroupLabel.exists?(name: "営業")
    end

    delete management_group_path(@company)
    assert_redirected_to management_groups_path
  end

  test "「全員」グループは削除できない" do
    login(@admin)
    get confirm_destroy_management_group_path(@everyone)
    assert_response :not_found
    delete management_group_path(@everyone)
    assert_response :not_found
  end

  test "利用停止の確認を経て停止すると、下位ごとツリーから消え、停止中の詳細に移る" do
    login(@admin)
    get edit_management_group_path(@sales)
    assert_select "#suspend-group[href=?]", confirm_suspend_management_group_path(@sales)

    get confirm_suspend_management_group_path(@sales)
    assert_select "#suspend-confirmation", text: /「営業本部」を利用停止にします。/
    assert_select "#suspend-confirmation", text: /下位グループ 2件も一緒に停止されます。/

    post suspend_management_group_path(@sales)
    assert_redirected_to management_group_path(@sales)
    follow_redirect!
    assert_select "[role=status]", text: "利用停止にしました。"
    assert_select "#group-tree", text: /営業本部|第一営業部/, count: 0
    assert_select "#suspension", text: /利用停止中です.*管理者さん/m
    assert_select "#suspension form[action=?] button:not([disabled])", reactivate_management_group_path(@sales)
    assert_select "#edit-group, #add-child-group", 0

    TenantContext.switch(tenant: @tenant) do
      assert_equal [@sales.id] * 3, [@sales, @sales1, @sales2].map { it.reload.suspension_root_id }
      assert_equal @admin_member, @sales.suspended_by
    end
  end

  test "停止中のグループは編集・削除・停止ができない" do
    login(@admin)
    [edit_management_group_path(@planning), confirm_destroy_management_group_path(@planning),
     confirm_suspend_management_group_path(@planning), member_candidates_management_group_path(@planning)].each do |path|
      get path
      assert_response :not_found
    end
    patch management_group_path(@planning), params: { group: { name: "新企画部", parent_id: @company.id } }
    assert_response :not_found
    delete management_group_path(@planning)
    assert_response :not_found
    post suspend_management_group_path(@planning)
    assert_response :not_found
    post reactivate_management_group_path(@sales)
    assert_response :not_found
  end

  test "起点を再開すると一緒に止まった下位も戻る。下位からは再開できず、起点へ案内する" do
    TenantContext.switch(tenant: @tenant) { @sales.suspend!(by: @admin_member) }
    login(@admin)

    get management_group_path(@sales1)
    assert_select "#suspension", text: /「営業本部」と一緒に停止されています。再開は「営業本部」から/
    assert_select "#suspension a[href=?]", management_group_path(@sales)
    assert_select "#suspension form", 0

    post reactivate_management_group_path(@sales)
    assert_redirected_to management_group_path(@sales)
    follow_redirect!
    assert_select "[role=status]", text: "再開しました。"
    assert_select "#group-tree a", text: "第一営業部"
  end

  test "上位が停止中か、同じ名前の有効なグループがあるときは、再開を押せずにわけを出す" do
    TenantContext.switch(tenant: @tenant) do
      @sales1.suspend!(by: @admin_member)
      @sales.suspend!(by: @admin_member)
    end
    login(@admin)

    get management_group_path(@sales1)
    assert_select "#suspension", text: /上位の「営業本部」が停止中のため再開できません/
    assert_select "#suspension button[disabled]", text: "再開する"
    post reactivate_management_group_path(@sales1)
    TenantContext.switch(tenant: @tenant) { assert @sales1.reload.suspended? }

    post reactivate_management_group_path(@sales)
    post management_groups_path, params: { group: { name: "第一営業部", parent_id: @sales.id } }
    get management_group_path(@sales1)
    assert_select "#suspension", text: /同じ名前の有効なグループがあるため再開できません/
    assert_select "#suspension button[disabled]"
  end

  test "停止中の一覧は停止日時の新しい順に起点だけを出し、チェックで一緒に止まった下位も出す" do
    TenantContext.switch(tenant: @tenant) do
      @planning.update_columns(suspended_at: 2.days.ago)
      @sales.suspend!(by: @admin_member)
    end
    login(@admin)

    get management_groups_path
    assert_select "#suspended-groups-link[href=?]", suspended_management_groups_path

    get suspended_management_groups_path
    assert_response :success
    assert_select "#suspended-groups tbody tr", 2
    assert_select "#suspended-groups tbody tr:first-child", text: /営業本部\s*下位グループ 2件も一緒に停止\s*全社.*管理者さん/m
    assert_select "#suspended-groups tbody tr:last-child", text: /旧企画部/
    assert_select "#suspended-groups", text: /第一営業部/, count: 0

    get suspended_management_groups_path(include_descendants: 1)
    # 同じ操作で止まった行は、起点からツリーの浅い順に並ぶ
    assert_equal %w[営業本部 第一営業部 第二営業部 旧企画部], css_select("#suspended-groups tbody tr td:first-child a").map(&:text)
    assert_select "#suspended-groups tbody tr", text: /第一営業部\s*「営業本部」と一緒に停止\s*全社 > 営業本部/
    assert_select "#include_descendants[checked]"
  end

  test "停止中の一覧はグループ名と停止した時点の上位で探し、下位にだけ当たるときはチェックへ誘う" do
    TenantContext.switch(tenant: @tenant) do
      @sales.suspend!(by: @admin_member)
      # 停止した後に上位の名前が変わっても、停止した時点の名前で探せる
      @company.update!(name: "本社")
    end
    login(@admin)

    get suspended_management_groups_path(q: "全社")
    assert_select "#suspended-groups tbody tr", 2
    assert_select "input#q[value=?]", "全社"

    get suspended_management_groups_path(q: "第一")
    assert_select "#suspended-groups", 0
    assert_select "#hidden-matches", text: /一緒に停止された下位グループに 1件あります/
    assert_select "#hidden-matches a[href=?]", suspended_management_groups_path(q: "第一", include_descendants: 1)

    get suspended_management_groups_path(q: "第一", include_descendants: 1)
    assert_select "#suspended-groups tbody tr", 1

    get suspended_management_groups_path(q: "%")
    assert_select "#suspended-groups", 0
    assert_select "#hidden-matches", 0
  end

  test "停止中の一覧は30件ずつ返し、続きは条件を付けて読み足す" do
    TenantContext.switch(tenant: @tenant) do
      31.times { |i| Group.create!(tenant: @tenant, name: format("旧プロジェクト%02d", i)).suspend!(by: @admin_member) }
    end
    login(@admin)

    get suspended_management_groups_path(q: "旧")
    assert_select "#suspended-groups tbody tr:not([data-load-more])", 30
    assert_select "tr[data-load-more=?]", suspended_management_groups_path(q: "旧", page: 2)

    get suspended_management_groups_path(q: "旧", page: 2)
    # 表の外の tr は assert_select の解析で落ちるので、文字列で数える（旧企画部と、31件の残り1件）
    assert_not_includes response.body, "<html"
    assert_equal 2, response.body.scan("<tr").size
    assert_not_includes response.body, "data-load-more"
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
      assert_select "input#group_name:not([value])"
      assert_select "#group-parent summary", text: /全社\s*>\s*営業本部\s*>\s*第一営業部/
      assert_select "select#group_parent_id option[selected]", text: /第一営業部/
      assert_select "label-input input#group_label_names[value='']"
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

  test "自分の他のテナントでの所属は、候補にも「全員」の人数にも入れない" do
    # tenant_users は RLS でも、ログインしている人の他のテナントでの所属が見える
    other = Tenant.setup!(name: "テナントB")
    TenantContext.switch(tenant: other) do
      TenantUser.create!(tenant: other, user: @admin, display_name: "Bの管理者さん", role: :admin, status: :active)
    end
    post login_path, params: { email: @admin.email, password: PASSWORD }
    post select_tenant_path, params: { tenant_id: @tenant.id }

    get member_candidates_management_group_path(@sales)
    assert_select "li input[type=checkbox]", 6
    assert_select "li", text: /Bの管理者さん/, count: 0
    get management_group_path(@everyone)
    assert_select "p", text: /全員（6人）/
  end

  test "グループ管理者には、管理のメニューにグループ管理だけを出す。グループ管理者でない人は開けない" do
    login(sato)
    get top_page_path
    assert_select "dialog[data-drawer] nav a[href=?]", management_groups_path, text: "管理"

    get management_groups_path
    assert_response :success
    assert_select "#side-pane a", 1
    assert_select "#side-pane a[aria-current=page]", text: "グループ管理"
    [management_users_path, management_tenant_setting_path].each do |path|
      get path
      assert_response :not_found
    end

    delete logout_path
    login(@people["山田"].user)
    get top_page_path
    assert_select "dialog[data-drawer] nav", text: /管理/, count: 0
    get management_groups_path
    assert_response :not_found
  end

  test "グループ管理者のツリーは範囲の中だけで、範囲の外の詳細は開けない" do
    login(sato)
    get management_groups_path
    assert_select "#group-tree > details > summary a", text: "営業本部"
    assert_select "#group-tree a", text: /全社|開発|全員/, count: 0
    assert_select "#everyone-group", 0
    assert_select "#new-group", 0

    [@company, @dev, @everyone].each do |group|
      get management_group_path(group)
      assert_response :not_found
    end
    get management_group_path(@sales1)
    assert_response :success
  end

  test "グループ管理者は範囲の中を編集・作成できるが、最上位や範囲の外には置けない" do
    login(sato)

    patch management_group_path(@sales1), params: { group: {
      name: "法人営業部", parent_id: @sales.id, label_names: "", members: { @people["田中"].id => "leader" },
    } }
    assert_redirected_to management_group_path(@sales1)

    post management_groups_path, params: { group: { name: "第三営業部", parent_id: @sales.id, label_names: "" } }
    assert_response :redirect
    get new_management_group_path(parent_id: @sales2.id)
    assert_response :success

    # 最上位と範囲の外には作れない
    get new_management_group_path
    assert_response :not_found
    post management_groups_path, params: { group: { name: "新しい部", parent_id: "", label_names: "" } }
    assert_response :not_found
    post management_groups_path, params: { group: { name: "新しい部", parent_id: @dev.id, label_names: "" } }
    assert_response :not_found

    # 範囲の中へは移せるが、範囲の外へは移せない
    patch management_group_path(@sales2), params: { group: { name: "第二営業部", parent_id: @sales1.id, label_names: "" } }
    assert_redirected_to management_group_path(@sales2)
    patch management_group_path(@sales), params: { group: { name: "営業本部", parent_id: @dev_hq.id, label_names: "" } }
    assert_response :not_found
    TenantContext.switch(tenant: @tenant) { assert_equal @company, @sales.reload.parent }
  end

  test "グループ管理者が自分のグループを編集するとき、範囲の外の今の上位はそのまま選ばれている" do
    login(sato)
    get edit_management_group_path(@sales)
    assert_select "select#group_parent_id option[selected]", text: "全社"
    assert_select "select#group_parent_id option[value='']", 0
    assert_select "select#group_parent_id option", text: /開発/, count: 0

    patch management_group_path(@sales), params: { group: {
      name: "営業統括本部", parent_id: @company.id, label_names: "", members: { @people["佐藤"].id => "leader" },
    } }
    assert_redirected_to management_group_path(@sales)
  end

  test "グループ管理者は自分のグループそのものは消せず、その下位は消せる" do
    login(sato)
    get edit_management_group_path(@sales)
    assert_select "#destroy-group", 0
    get confirm_destroy_management_group_path(@sales)
    assert_response :not_found
    delete management_group_path(@sales)
    assert_response :not_found

    get edit_management_group_path(@sales1)
    assert_select "#destroy-group"
    delete management_group_path(@sales1)
    assert_redirected_to management_group_path(@sales)
  end

  test "グループ管理者は自分のグループを停止・再開でき、停止中の一覧には範囲の中だけが出る" do
    TenantContext.switch(tenant: @tenant) { @dev.suspend!(by: @admin_member) }
    login(sato)

    post suspend_management_group_path(@sales)
    assert_redirected_to management_group_path(@sales)
    get suspended_management_groups_path(include_descendants: 1)
    assert_equal %w[営業本部 第一営業部 第二営業部], css_select("#suspended-groups tbody tr td:first-child a").map(&:text)

    post reactivate_management_group_path(@sales)
    TenantContext.switch(tenant: @tenant) { assert_not @sales.reload.suspended? }
  end

  test "グループ管理者が自分の印を外すと、開けるところへ戻る" do
    TenantContext.switch(tenant: @tenant) do
      GroupMember.create!(tenant: @tenant, group: @dev, tenant_user: @people["佐藤"], role: :leader)
    end
    login(sato)

    # まだ開発部を管理しているので、グループ管理の一覧へ
    patch management_group_path(@sales), params: { group: {
      name: "営業本部", parent_id: @company.id, label_names: "", members: { @people["佐藤"].id => "member" },
    } }
    assert_redirected_to management_groups_path

    # どこも管理しなくなったので、トップへ
    patch management_group_path(@dev), params: { group: {
      name: "開発部", parent_id: @dev_hq.id, label_names: "", members: { @people["佐藤"].id => "member" },
    } }
    assert_redirected_to top_page_path
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

  # 営業本部のグループ管理者
  def sato
    @people["佐藤"].user
  end

  def login(user)
    post login_path, params: { email: user.email, password: PASSWORD }
    follow_redirect!
    follow_redirect!
  end
end
