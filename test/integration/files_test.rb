require "test_helper"

class FilesTest < ActionDispatch::IntegrationTest
  PASSWORD = "password1234".freeze

  setup do
    @tenant = Tenant.setup!(name: "テナントA")
    @owner_user = User.create!(email: "owner@example.com", password: PASSWORD)
    @member_user = User.create!(email: "member@example.com", password: PASSWORD)

    TenantContext.switch(tenant: @tenant) do
      @owner = TenantUser.create!(
        tenant: @tenant, user: @owner_user, display_name: "管理者さん", role: :owner, status: :active,
      )
      @member = TenantUser.create!(
        tenant: @tenant, user: @member_user, display_name: "一般さん", role: :member, status: :active,
      )
      @root = Files::Drive.shared_root(@tenant)
      @everyone = Group.everyone_of(@tenant)
      @sales = node(:folder, "営業", @root)
      @estimates = node(:folder, "見積", @sales)
      @hr = node(:folder, "人事", @root)
      @review = node(:file, "評価.xlsx", @hr)
      @minutes = node(:file, "議事録.docx", @root, byte_size: 25_088)
      grant(@hr, @everyone, :none)
    end
  end

  teardown do
    TenantContext.clear
  end

  describe "フォルダ" do
    test "組織共有ドライブのルートを一覧する" do
      login(@member_user)
      get files_root_path

      assert_response :success
      assert_select "h1", "組織共有ドライブ"
      assert_select "#file-list tbody tr", 3
      assert_select "#file-list tbody tr:nth-child(1) td:first-child", /営業/
      assert_select "#file-list tbody tr:nth-child(2) td:first-child", /人事/
      assert_select "#file-list tbody tr:nth-child(3) td", "24.5 KB"
      assert_select "#file-list tbody tr:nth-child(1) td", "-"
      assert_select "#file-list tbody tr:nth-child(3) td", "管理者さん"
    end

    test "権限の無いフォルダは名前だけ出して開けない" do
      login(@member_user)
      get files_root_path

      assert_select "#file-list a[href=?]", files_folder_path(@sales)
      assert_select "#file-list a[href=?]", files_folder_path(@hr), 0
      assert_select "#file-list td", text: /人事/
    end

    test "権限の無いファイルは一覧に出さない" do
      TenantContext.switch(tenant: @tenant) { grant(@minutes, @everyone, :none) }
      login(@member_user)
      get files_root_path

      assert_select "#file-list td", text: /議事録/, count: 0
    end

    test "サブフォルダではパンくずに上位のフォルダが出る" do
      login(@member_user)
      get files_folder_path(@estimates)

      assert_select "h1", "見積"
      assert_select "nav[aria-label=?] a", "現在の場所", 2
      assert_select "nav[aria-label=?] a[href=?]", "現在の場所", files_folder_path(@root), text: "組織共有ドライブ"
      assert_select "nav[aria-label=?] a[href=?]", "現在の場所", files_folder_path(@sales), text: "営業"
      assert_select "#file-list + p", "このフォルダには何もありません"
    end

    test "権限の無いフォルダを開くと404" do
      login(@member_user)
      get files_folder_path(@hr)

      assert_response :not_found
    end

    test "存在しないフォルダやファイルを開くと404" do
      login(@member_user)

      get files_folder_path(0)
      assert_response :not_found

      get files_folder_path(@minutes)
      assert_response :not_found
    end

    test "編集者にだけ作成ボタンを出す" do
      login(@member_user)
      get files_folder_path(@sales)
      assert_select "button", text: "作成", count: 0

      TenantContext.switch(tenant: @tenant) { grant(@sales, @member, :editor) }
      get files_folder_path(@sales)
      assert_select "button", text: "作成"
    end

    test "テナント管理者は権限の無いフォルダも開ける" do
      login(@owner_user)
      get files_root_path

      assert_select "#file-list a[href=?]", files_folder_path(@hr)
    end
  end

  describe "マイドライブ" do
    test "初めて開いたときに作られ、他の利用者は開けない" do
      login(@member_user)
      get files_my_drive_path

      assert_response :success
      assert_select "h1", "マイドライブ"
      assert_select "button", text: "作成"

      root = TenantContext.switch(tenant: @tenant) { Files::Drive.personal.find_by!(owner: @member).root }
      delete logout_path
      TenantContext.switch(tenant: @tenant) { @owner.update!(role: :member) }
      login(@owner_user)
      get files_folder_path(root)
      assert_response :not_found
    end
  end

  describe "左ペイン" do
    test "ドライブの直下のフォルダを並べ、開いている場所を示す" do
      login(@member_user)
      get files_folder_path(@sales)

      assert_select "aside", text: /\Aファイル\s*組織共有ドライブ.*共有されたアイテム.*マイドライブ.*ゴミ箱/m
      assert_select "aside details[open]", 1
      assert_select "aside details[open] a[aria-current=page]", "組織共有ドライブ"
      assert_select "aside details[open] a[href=?]", files_folder_path(@sales), text: "営業"
      assert_select "aside details[open] a[href=?]", files_folder_path(@hr), 0
    end
  end

  describe "共有されたアイテム" do
    test "親が見えず自分に共有されたものを並べる" do
      TenantContext.switch(tenant: @tenant) { grant(@review, @member, :viewer) }
      login(@member_user)
      get files_shared_items_path

      assert_response :success
      assert_select "h1", "共有されたアイテム"
      assert_select "#file-list tbody tr", 1
      assert_select "#file-list td", text: /評価\.xlsx/
    end

    test "共有されたフォルダを開くと、パンくずは共有されたアイテムから始まる" do
      shared = TenantContext.switch(tenant: @tenant) do
        node(:folder, "面談", @hr).tap { |folder| grant(folder, @member, :viewer) }
      end
      login(@member_user)
      get files_folder_path(shared)

      assert_response :success
      assert_select "nav[aria-label=?] a", "現在の場所", 1
      assert_select "nav[aria-label=?] a[href=?]", "現在の場所", files_shared_items_path
      assert_select "nav[aria-label=?]", "現在の場所", text: /人事/, count: 0
    end

    test "無ければその旨を出す" do
      login(@member_user)
      get files_shared_items_path

      assert_select "#file-list + p", "共有されたアイテムはありません"
    end
  end

  describe "ゴミ箱" do
    test "親フォルダの編集者には削除したものが出る" do
      TenantContext.switch(tenant: @tenant) do
        grant(@sales, @member, :editor)
        trashed = node(:file, "古い見積.pdf", @sales)
        trashed.update!(deleted_at: Time.current, deleted_root_id: trashed.id, deleted_by: @owner)
      end
      login(@member_user)
      get files_trash_path

      assert_response :success
      assert_select "#file-list tbody tr", 1
      assert_select "#file-list td", text: /古い見積\.pdf/
      assert_select "#file-list td", "管理者さん"
      assert_select "#file-list a", 0
    end

    test "閲覧者には出ない" do
      TenantContext.switch(tenant: @tenant) do
        trashed = node(:file, "古い見積.pdf", @sales)
        trashed.update!(deleted_at: Time.current, deleted_root_id: trashed.id)
      end
      login(@member_user)
      get files_trash_path

      assert_select "#file-list + p", "ゴミ箱は空です"
    end
  end

  describe "入口" do
    test "メニューの「ファイル」から開ける" do
      login(@member_user)
      get top_page_path

      assert_select "dialog[data-drawer] a[href=?]", files_root_path
    end

    test "テナント未選択でアクセスすると、選択後に元のページへ戻る" do
      other = Tenant.setup!(name: "テナントB")
      TenantContext.switch(tenant: other) do
        TenantUser.create!(tenant: other, user: @member_user, display_name: "一般さん", status: :active)
      end
      post login_path, params: { email: @member_user.email, password: PASSWORD }

      get files_root_path
      assert_redirected_to select_tenant_path

      post select_tenant_path, params: { tenant_id: @tenant.id }
      assert_redirected_to files_root_path
    end

    test "未ログインでは開けない" do
      get files_root_path

      assert_redirected_to login_path
    end
  end

  private

  def login(user)
    post login_path, params: { email: user.email, password: PASSWORD }
    follow_redirect!
    follow_redirect!
  end

  def node(kind, name, parent, byte_size: 0)
    Files::Node.create!(
      tenant: @tenant, drive: parent.drive, parent: parent, kind: kind, name: name,
      creator: @owner, byte_size: byte_size,
    )
  end

  def grant(node, subject, role)
    subject_key = subject.is_a?(Group) ? :group : :tenant_user
    Files::Permission.create!(tenant: @tenant, node: node, subject_key => subject, role: role)
  end
end
