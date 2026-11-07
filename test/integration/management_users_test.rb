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
    # 名前を見出しにしてメールアドレスを添え、有効なら状態の印は出さない。権限は行で出す
    assert_select "#user-header h2", text: "佐藤さん"
    assert_select "#user-header p", text: "sato@example.com"
    assert_select "#user-header", text: /有効|招待中|停止中/, count: 0
    assert_select "#user-detail dd", text: "メンバー"
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
    assert_select "pick-list[data-candidates-url=?]", group_candidates_management_users_path do
      assert_select "button#add-groups", text: "所属グループを追加"
      assert_select "tbody tr[data-row]", 0
    end
    assert_select "#user-form input[type=radio][name=?]", "tenant_user[role]", 2
    assert_select "#user-form input[type=radio][value=member][checked]"

    post management_users_path, params: { tenant_user: {
      email: "new@example.com", display_name: "新人さん", role: "member", group_ids: ["", @sales.id, @dev.id],
    } }
    tenant_user = TenantContext.switch(tenant: @tenant) { TenantUser.find_by!(display_name: "新人さん") }
    assert_redirected_to management_user_path(tenant_user)
    follow_redirect!
    assert_select "#user-header", text: /招待中/
    assert_equal ["営業部 全社", "開発部 全社"], css_select("#user-groups tr").map { it.text.squish }
  end

  test "所属グループの候補は、有効なグループをグループ名で探し、上位の並びを添えて1ページずつ返す" do
    login(@admin)
    get group_candidates_management_users_path
    assert_response :success
    assert_not_includes response.body, "<html"
    # 停止中のグループと「全員」は出さない
    # 上位の並びの順（全社の下に営業部・開発部）
    assert_equal ["全社", "営業部 全社", "開発部 全社"], css_select("li").map { it.text.squish }
    assert_select "li input[type=checkbox][value=?][data-name=?][data-detail=?]", @sales.id.to_s, "営業部", "全社"

    get group_candidates_management_users_path(q: "営業")
    assert_equal ["営業部 全社"], css_select("li").map { it.text.squish }

    TenantContext.switch(tenant: @tenant) { 31.times { Group.create!(tenant: @tenant, parent: @dev, name: format("チーム%02d", it)) } }
    get group_candidates_management_users_path(q: "チーム")
    assert_select "li:not([data-load-more])", 30
    assert_select "li[data-load-more=?]", group_candidates_management_users_path(q: "チーム", page: 2)
    get group_candidates_management_users_path(q: "チーム", page: 2)
    assert_select "li", 1
  end

  test "利用者にラベルを付けると、一覧と詳細に出し、編集で付け直せる。候補は利用者のラベルだけ" do
    TenantContext.switch(tenant: @tenant) { GroupLabel.create!(tenant: @tenant, name: "本部") }
    login(@admin)
    get new_management_user_path
    assert_select "#user-form label-input input[name=?]", "tenant_user[label_names]"
    assert_select "#user-form label-input[data-suggestions=?]", "[]"

    post management_users_path, params: { tenant_user: {
      email: "guest@example.com", display_name: "ゲストさん", role: "member", label_names: "ゲスト、A社", group_ids: [""],
    } }
    guest = TenantContext.switch(tenant: @tenant) { TenantUser.find_by!(display_name: "ゲストさん") }
    follow_redirect!
    assert_select "#user-header #user-labels li", text: /\A(A社|ゲスト)\z/, count: 2
    get management_users_path
    assert_select "#user-list tr", text: /ゲストさん\s*A社\s*ゲスト/

    get edit_management_user_path(guest)
    assert_select "#user-form input[name=?][value=?]", "tenant_user[label_names]", "A社, ゲスト"
    assert_select "#user-form label-input[data-suggestions=?]", %w[A社 ゲスト].to_json
    patch management_user_path(guest), params: { tenant_user: { display_name: "ゲストさん", role: "member", label_names: "B社", group_ids: [""] } }
    assert_equal ["B社"], TenantContext.switch(tenant: @tenant) { guest.labels.pluck(:name) }

    # ラベルが無ければ欄ごと出さない
    get management_user_path(@sato)
    assert_select "#user-labels", 0
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
    assert_equal [@dev.id.to_s], css_select("#user-groups tbody tr").map { it["data-row"] }
  end

  test "管理者はオーナーを追加できない" do
    login(@admin)
    get new_management_user_path
    assert_select "#user-form input[type=radio][value=owner]", 0

    post management_users_path, params: { tenant_user: { email: "new@example.com", display_name: "新人さん", role: "owner" } }
    assert_response :not_found
  end

  test "オーナーはオーナーを追加できる" do
    owner = TenantContext.switch(tenant: @tenant) do
      TenantUser.create!(tenant: @tenant, user: User.create!(email: "owner@example.com", password: PASSWORD),
        display_name: "オーナーさん", role: :owner, status: :active)
    end
    login(owner.user)
    get new_management_user_path
    assert_select "#user-form input[type=radio][name=?]", "tenant_user[role]", 3
    assert_select "#user-form label", text: "オーナー"

    post management_users_path, params: { tenant_user: { email: "new@example.com", display_name: "新人さん", role: "owner" } }
    assert TenantContext.switch(tenant: @tenant) { TenantUser.find_by!(display_name: "新人さん").owner? }
  end

  test "編集の画面から確認の画面を経て削除すると、一覧から消え、テナントにも入れなくなる" do
    login(@admin)
    get edit_management_user_path(@sato)
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

  test "削除した人を同じメールアドレスで加え直すと、新しい所属になり、元の所属は削除済みのまま残る" do
    login(@admin)
    delete management_user_path(@sato)
    post management_users_path, params: { tenant_user: {
      email: "sato@example.com", display_name: "戻った佐藤さん", role: "member", group_ids: [""],
    } }

    readded = TenantContext.switch(tenant: @tenant) { TenantUser.not_deleted.find_by!(user: @sato.user) }
    assert_redirected_to management_user_path(readded)
    assert_not_equal @sato.id, readded.id
    assert TenantContext.switch(tenant: @tenant) { @sato.reload.deleted? }
    get management_users_path
    assert_select "#user-list tbody tr", text: /佐藤さん/, count: 1
  end

  test "オーナーと自分自身は削除できない" do
    owner = TenantContext.switch(tenant: @tenant) do
      TenantUser.create!(tenant: @tenant, user: User.create!(email: "owner@example.com", password: PASSWORD),
        display_name: "オーナーさん", role: :owner, status: :active)
    end
    login(@admin)

    [owner, @admin_member].each do |tenant_user|
      get edit_management_user_path(tenant_user)
      assert_select "#destroy-user", 0
      get confirm_destroy_management_user_path(tenant_user)
      assert_response :not_found
      delete management_user_path(tenant_user)
      assert_response :not_found
    end
    assert TenantContext.switch(tenant: @tenant) { owner.reload.active? }
  end

  test "詳細の「編集」から、表示名・権限・所属グループを変える。停止中のグループの所属とグループ管理者の印は残す" do
    TenantContext.switch(tenant: @tenant) { GroupMember.create!(tenant: @tenant, group: @company, tenant_user: @sato) }
    login(@admin)
    get management_user_path(@sato)
    assert_select "a#edit-user[href=?]", edit_management_user_path(@sato)

    get edit_management_user_path(@sato)
    assert_response :success
    # 誰の編集かは、変えられないメールアドレスで示す。表示名はすぐ下の入力欄にあるので見出しに出さない
    assert_select "#user-header", text: "sato@example.com"
    assert_select "#user-form input[name=?]", "tenant_user[email]", 0
    assert_equal %w[member admin], css_select("#role-choices input").map { it["value"] }
    # 停止は「利用停止」の操作で行うので、有効な人の状態は選べない
    assert_select "#status-choices input", 0
    assert_select "#status-choices p", text: "有効"
    # 停止中の旧企画部の所属は出さない
    assert_equal ["全社", "営業部 全社"], css_select("#user-groups tbody tr").map { it.text.squish.delete_suffix(" 削除") }
    assert_select "#user-groups tbody tr[data-row=?] input[type=hidden][name=?][value=?]", @sales.id.to_s,
      "tenant_user[group_ids][]", @sales.id.to_s

    patch management_user_path(@sato), params: { tenant_user: {
      display_name: "佐藤花子さん", role: "admin", group_ids: ["", @sales.id, @dev.id],
    } }
    assert_redirected_to management_user_path(@sato)

    TenantContext.switch(tenant: @tenant) do
      @sato.reload
      assert_equal ["佐藤花子さん", "admin", "active"], @sato.values_at(:display_name, :role, :status)
      roles = GroupMember.where(tenant_user: @sato).to_h { [it.group_id, it.role] }
      assert_equal({ @sales.id => "leader", @dev.id => "member", @planning.id => "member" }, roles)
    end
  end

  test "招待中の人は、有効にできる" do
    invited = TenantContext.switch(tenant: @tenant) do
      TenantUser.create!(tenant: @tenant, user: User.create!(email: "new@example.com", password: PASSWORD),
        display_name: "新人さん", status: :invited)
    end
    login(@admin)
    get edit_management_user_path(invited)
    assert_equal %w[invited active], css_select("#status-choices input").map { it["value"] }

    patch management_user_path(invited), params: { tenant_user: { display_name: "新人さん", role: "member", status: "active", group_ids: [""] } }
    assert TenantContext.switch(tenant: @tenant) { invited.reload.active? }
  end

  test "管理者は、オーナーの権限・状態を変えられず、オーナーにもできない" do
    owner = create_owner("owner@example.com", "オーナーさん")
    login(@admin)

    get edit_management_user_path(owner)
    assert_select "#role-choices input", 0
    assert_select "#role-choices p", text: "オーナー"
    assert_select "#status-choices input", 0

    [{ role: "admin" }, { status: "suspended" }].each do |change|
      patch management_user_path(owner), params: { tenant_user: { display_name: "オーナーさん", group_ids: [""], **change } }
      assert_response :not_found
    end
    patch management_user_path(@sato), params: { tenant_user: { display_name: "佐藤さん", role: "owner", status: "active", group_ids: [""] } }
    assert_response :not_found
    assert TenantContext.switch(tenant: @tenant) { owner.reload.owner? && !@sato.reload.owner? }
  end

  test "オーナーは、他のオーナーを管理者にできるが、有効なオーナーが1人もいなくなる変更はできない" do
    owner = create_owner("owner@example.com", "オーナーさん")
    other = create_owner("owner2@example.com", "二人目のオーナーさん")
    login(owner.user)

    get edit_management_user_path(other)
    assert_equal %w[member admin owner], css_select("#role-choices input").map { it["value"] }
    patch management_user_path(other), params: { tenant_user: { display_name: "二人目のオーナーさん", role: "admin", status: "active", group_ids: [""] } }
    assert_redirected_to management_user_path(other)

    # 残った自分を管理者に下げると、有効なオーナーがいなくなる
    patch management_user_path(owner), params: { tenant_user: { display_name: "オーナーさん", role: "admin", group_ids: [""] } }
    assert_response :unprocessable_entity
    assert_select "[role=alert]", text: /有効なオーナーが1人もいなくなるため/
    assert_select "#role-choices input[value=admin][checked]"
    assert TenantContext.switch(tenant: @tenant) { owner.reload.owner? }
  end

  test "自分の状態は変えられないが、権限は下げられる。メンバーに下げたら管理の画面を離れる" do
    login(@admin)
    get edit_management_user_path(@admin_member)
    assert_select "#status-choices input", 0
    patch management_user_path(@admin_member), params: { tenant_user: { display_name: "管理者さん", status: "suspended", group_ids: [""] } }
    assert_response :not_found

    patch management_user_path(@admin_member), params: { tenant_user: { display_name: "管理者さん", role: "member", group_ids: [""] } }
    assert_redirected_to top_page_path
    get management_users_path
    assert_response :not_found
  end

  test "表示名が空なら、入力したとおりに出し直す" do
    login(@admin)
    patch management_user_path(@sato), params: { tenant_user: { display_name: "", role: "admin", status: "active", group_ids: ["", @dev.id] } }

    assert_response :unprocessable_entity
    assert_select "[role=alert]", text: /表示名/
    assert_select "#role-choices input[value=admin][checked]"
    assert_equal [@dev.id.to_s], css_select("#user-groups tbody tr").map { it["data-row"] }
    assert TenantContext.switch(tenant: @tenant) { @sato.reload.member? }
  end

  test "編集の画面から確認の画面を経て利用停止にすると、一覧から外れて「利用停止中の利用者」に出る。再開すると戻る" do
    login(@admin)
    get edit_management_user_path(@sato)
    assert_select "a#suspend-user[href=?]", confirm_suspend_management_user_path(@sato)

    get confirm_suspend_management_user_path(@sato)
    assert_select "#suspend-confirmation", text: /「佐藤さん」（sato@example.com）を利用停止にします。/
    post suspend_management_user_path(@sato)
    assert_redirected_to management_user_path(@sato)
    follow_redirect!
    assert_select "#suspension", text: /利用停止中です。.*管理者さんが停止しました。/m
    # 停止中は編集できず、詳細から再開か削除をする
    assert_select "#edit-user", 0
    assert_select "#suspension form[action=?] button", reactivate_management_user_path(@sato), text: "再開する"
    assert_select "#suspension a#destroy-user[href=?]", confirm_destroy_management_user_path(@sato)
    get edit_management_user_path(@sato)
    assert_response :not_found
    # 所属グループは残る
    assert TenantContext.switch(tenant: @tenant) { GroupMember.exists?(tenant_user: @sato, group: @sales) }

    get management_users_path
    assert_select "#user-list", text: /佐藤さん/, count: 0
    assert_select "a#suspended-users[href=?]", suspended_management_users_path
    get suspended_management_users_path
    assert_select "#suspended-users tbody tr", 1
    assert_select "#suspended-users tbody tr", text: /佐藤さん.*sato@example.com.*管理者さん/m

    post reactivate_management_user_path(@sato)
    assert_redirected_to management_user_path(@sato)
    assert TenantContext.switch(tenant: @tenant) { @sato.reload.active? && @sato.suspended_at.nil? }
    get management_users_path
    assert_select "#user-list", text: /佐藤さん/
  end

  test "利用停止中の利用者は、表示名・メールアドレスで探せ、新しく止めた順に30件ずつ出す" do
    TenantContext.switch(tenant: @tenant) do
      35.times do |i|
        TenantUser.create!(tenant: @tenant, user: User.create!(email: "s#{i}@example.com", password: PASSWORD),
          display_name: format("停止%02d", i), status: :suspended, suspended_at: i.minutes.ago)
      end
    end
    login(@admin)

    get suspended_management_users_path
    assert_select "#suspended-users tbody tr:not([data-load-more])", 30
    assert_select "#suspended-users tbody tr:first-child", text: /停止00/
    assert_select "tr[data-load-more=?]", suspended_management_users_path(page: 2)
    get suspended_management_users_path(page: 2)
    # 表の外の tr は assert_select の解析で落ちるので、文字列で数える
    assert_not_includes response.body, "<html"
    assert_equal 5, response.body.scan("<tr").size

    get suspended_management_users_path(q: "s12@")
    assert_select "#suspended-users tbody tr", 1
    get suspended_management_users_path(q: "いない人")
    assert_select "p", text: "当てはまる利用者はいません。"
  end

  test "停止中の人は、詳細からそのまま削除できる" do
    TenantContext.switch(tenant: @tenant) { @sato.suspend(by: @admin_member) }
    login(@admin)
    get confirm_destroy_management_user_path(@sato)
    assert_response :success
    # 停止中の人には「利用停止にしてください」とは書かない
    assert_select "#destroy-confirmation", text: /利用停止/, count: 0
    delete management_user_path(@sato)
    assert TenantContext.switch(tenant: @tenant) { @sato.reload.deleted? }
  end

  test "自分と招待中の人は利用停止にできず、オーナーを止められるのはオーナーだけ" do
    owner = create_owner("owner@example.com", "オーナーさん")
    invited = TenantContext.switch(tenant: @tenant) do
      TenantUser.create!(tenant: @tenant, user: User.create!(email: "new@example.com", password: PASSWORD),
        display_name: "新人さん", status: :invited)
    end
    login(@admin)

    [@admin_member, invited, owner].each do |tenant_user|
      get edit_management_user_path(tenant_user)
      assert_select "#suspend-user", 0
      post suspend_management_user_path(tenant_user)
      assert_response :not_found
    end
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

  def create_owner(email, display_name)
    TenantContext.switch(tenant: @tenant) do
      TenantUser.create!(tenant: @tenant, user: User.create!(email:, password: PASSWORD), display_name:,
        role: :owner, status: :active)
    end
  end

  def login(user)
    post login_path, params: { email: user.email, password: PASSWORD }
    follow_redirect!
    follow_redirect!
  end
end
