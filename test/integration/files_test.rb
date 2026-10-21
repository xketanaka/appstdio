require "test_helper"

# 画面の表示は Vue（app/javascript/files）が受け持つので、ここでは入れ物のページと
# API の応答を確かめる。表示のしかたは Vitest、通しの動きは system test で確かめる
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

  describe "入れ物のページ" do
    test "どの URL でも同じページを返し、Vue に設定を渡す" do
      login(@owner_user)

      [files_root_path, files_my_drive_path, files_folder_path(@sales), files_shared_items_path, files_trash_path].each do |path|
        get path
        assert_response :success
        assert_select "#files-app[data-config]", 1
      end

      config = JSON.parse(css_select("#files-app").first["data-config"])
      assert_equal "組織共有ドライブ", config.dig("messages", "sections", "shared_drive")
      assert config["admin_or_owner"]
      assert_not config["privileged"]
    end

    test "フォルダが無くても入れ物は返す。見つからない旨は API の応答を受けて Vue が出す" do
      login(@member_user)
      get files_folder_path(0)

      assert_response :success
    end

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

    test "未ログインではログイン画面へ転送する" do
      get files_root_path

      assert_redirected_to login_path
    end
  end

  describe "API の入口" do
    test "未ログインでは転送せず 401 を返す" do
      get files_api_tree_path

      assert_response :unauthorized
    end
  end

  describe "フォルダ" do
    test "組織共有ドライブのルートを一覧する" do
      login(@member_user)
      get files_api_drives_shared_path

      assert_response :success
      assert_equal({ "id" => @root.id, "label" => "組織共有ドライブ" }, json["folder"])
      assert_equal "shared_drive", json["section"]
      assert_equal ["営業", "人事", "議事録.docx"], json["entries"].pluck("name")
      assert_equal(
        { "kind" => "file", "readable" => true, "owner" => "管理者さん", "byte_size" => 25_088 },
        json["entries"].last.slice("kind", "readable", "owner", "byte_size"),
      )
      assert_nil json["entries"].first["byte_size"], "フォルダにサイズは無い"
    end

    test "権限の無い項目は名前だけを返し、付帯情報は返さない" do
      TenantContext.switch(tenant: @tenant) { grant(@minutes, @everyone, :none) }
      login(@member_user)
      get files_api_drives_shared_path

      hr, minutes = json["entries"].values_at(1, 2)
      [hr, minutes].each do |entry|
        assert_not entry["readable"]
        assert_nil entry["owner"]
        assert_nil entry["updated_at"]
        assert_nil entry["byte_size"]
      end
      assert_equal "議事録.docx", minutes["name"]
    end

    test "サブフォルダではパンくずに上位のフォルダが出る" do
      login(@member_user)
      get files_api_folder_path(@estimates)

      assert_equal "見積", json.dig("folder", "label")
      assert_equal ["組織共有ドライブ", "営業"], json["breadcrumbs"].pluck("label")
      assert_not json["via_shared"]
      assert_empty json["entries"]
    end

    test "権限の無いフォルダは 404" do
      login(@member_user)
      get files_api_folder_path(@hr)

      assert_response :not_found
    end

    test "存在しないフォルダやファイルは 404" do
      login(@member_user)

      get files_api_folder_path(0)
      assert_response :not_found

      get files_api_folder_path(@minutes)
      assert_response :not_found
    end

    test "編集できるかを返す" do
      login(@member_user)
      get files_api_folder_path(@sales)
      assert_not json["can_edit"]

      TenantContext.switch(tenant: @tenant) { grant(@sales, @member, :editor) }
      get files_api_folder_path(@sales)
      assert json["can_edit"]
    end
  end

  describe "フォルダの作成" do
    test "編集者はフォルダを作れ、作った人が管理者になる" do
      TenantContext.switch(tenant: @tenant) { grant(@sales, @member, :editor) }
      login(@member_user)
      post files_api_folders_path, params: { parent_id: @sales.id, name: "提案書" }, as: :json

      assert_response :created
      assert_equal "提案書", json["name"]
      get files_api_folder_path(json["id"])
      assert_response :success
      assert_equal "提案書", json.dig("folder", "label")
      assert json["can_edit"]
    end

    test "同じ名前や空の名前は 422 で理由を返す" do
      TenantContext.switch(tenant: @tenant) { grant(@sales, @member, :editor) }
      login(@member_user)

      post files_api_folders_path, params: { parent_id: @sales.id, name: "見積" }, as: :json
      assert_response :unprocessable_content
      assert_equal ["名前が同じフォルダの中のものと重複しています。"], json["errors"]

      post files_api_folders_path, params: { parent_id: @sales.id, name: "  " }, as: :json
      assert_response :unprocessable_content
      assert_equal ["名前が入力されていません。"], json["errors"]
    end

    test "閲覧者は 403、閲覧できないフォルダは 404" do
      login(@member_user)

      post files_api_folders_path, params: { parent_id: @sales.id, name: "提案書" }, as: :json
      assert_response :forbidden

      post files_api_folders_path, params: { parent_id: @hr.id, name: "提案書" }, as: :json
      assert_response :not_found
      assert_equal 0, TenantContext.switch(tenant: @tenant) { Files::Node.where(name: "提案書").count }
    end
  end

  describe "移動" do
    test "移動元の親と移動先の両方を編集できれば移せ、移動先の一覧に出る" do
      TenantContext.switch(tenant: @tenant) { grant(@root, @member, :editor) }
      login(@member_user)
      post move_files_api_nodes_path, params: { node_ids: [@minutes.id, @estimates.id], destination_id: @sales.id }, as: :json

      assert_response :no_content
      get files_api_folder_path(@sales)
      assert_equal ["見積", "議事録.docx"], json["entries"].pluck("name")
    end

    test "移動元か移動先のどちらかを編集できなければ 403" do
      TenantContext.switch(tenant: @tenant) { grant(@sales, @member, :editor) }
      login(@member_user)

      post move_files_api_nodes_path, params: { node_ids: [@estimates.id], destination_id: @root.id }, as: :json
      assert_response :forbidden, "移動先のルートは閲覧のみ"

      post move_files_api_nodes_path, params: { node_ids: [@minutes.id], destination_id: @sales.id }, as: :json
      assert_response :forbidden, "移動元のルートは閲覧のみ"
    end

    test "移せない理由は 422 で返す" do
      TenantContext.switch(tenant: @tenant) { grant(@root, @member, :editor) }
      login(@member_user)

      post move_files_api_nodes_path, params: { node_ids: [@sales.id], destination_id: @estimates.id }, as: :json

      assert_response :unprocessable_content
      assert_equal ["「営業」は、それ自身やその中のフォルダへは移動できません。"], json["errors"]
    end

    test "ドライブのルートや存在しないものは 404" do
      TenantContext.switch(tenant: @tenant) { grant(@root, @member, :editor) }
      login(@member_user)

      post move_files_api_nodes_path, params: { node_ids: [@root.id], destination_id: @sales.id }, as: :json
      assert_response :not_found

      post move_files_api_nodes_path, params: { node_ids: [0], destination_id: @sales.id }, as: :json
      assert_response :not_found
    end
  end

  describe "特権モード" do
    test "管理者は特権モードにすると権限の無いフォルダも開ける" do
      login(@owner_user)
      get files_api_folder_path(@hr)
      assert_response :not_found

      post files_api_privileged_mode_path
      assert_response :no_content

      get files_api_folder_path(@hr)
      assert_response :success
      get files_root_path
      assert JSON.parse(css_select("#files-app").first["data-config"])["privileged"]
    end

    test "終えると付与された権限での表示に戻る" do
      login(@owner_user)
      post files_api_privileged_mode_path

      delete files_api_privileged_mode_path
      assert_response :no_content

      get files_api_folder_path(@hr)
      assert_response :not_found
    end

    test "一般の利用者は切り替えられない" do
      login(@member_user)
      post files_api_privileged_mode_path

      assert_response :not_found
      get files_root_path
      assert_not JSON.parse(css_select("#files-app").first["data-config"])["admin_or_owner"]
    end

    test "テナントを切り替えると解除される" do
      other = Tenant.setup!(name: "テナントB")
      TenantContext.switch(tenant: other) do
        TenantUser.create!(tenant: other, user: @owner_user, display_name: "管理者さん", role: :owner, status: :active)
      end
      post login_path, params: { email: @owner_user.email, password: PASSWORD }
      post select_tenant_path, params: { tenant_id: @tenant.id }
      post files_api_privileged_mode_path

      post select_tenant_path, params: { tenant_id: other.id }
      post select_tenant_path, params: { tenant_id: @tenant.id }

      get files_api_folder_path(@hr)
      assert_response :not_found
    end
  end

  describe "マイドライブ" do
    test "初めて開いたときに作られ、他の利用者は開けない" do
      login(@member_user)
      get files_api_drives_mine_path

      assert_response :success
      assert_equal "マイドライブ", json.dig("folder", "label")
      assert_equal "my_drive", json["section"]
      assert json["can_edit"]

      root_id = json.dig("folder", "id")
      delete logout_path
      login(@owner_user)
      get files_api_folder_path(root_id)
      assert_response :not_found
    end
  end

  describe "左ペインのツリー" do
    test "ドライブのルートと直下のフォルダを、開けるか・子のフォルダがあるかと一緒に返す" do
      login(@member_user)
      get files_api_tree_path

      assert_equal @root.id, json.dig("shared_drive", "id")
      assert_equal(
        [
          { "id" => @sales.id, "name" => "営業", "readable" => true, "has_children" => true },
          { "id" => @hr.id, "name" => "人事", "readable" => false, "has_children" => false },
        ],
        json.dig("shared_drive", "folders"),
      )
      assert_nil json["my_drive"], "マイドライブはまだ作られていない"
    end

    test "指定した親の直下のフォルダを返す。開けないフォルダの中は返さない" do
      TenantContext.switch(tenant: @tenant) { node(:folder, "面談", @hr) }
      login(@member_user)
      get files_api_tree_children_path, params: { parent_ids: [@sales.id, @hr.id] }

      assert_equal [@sales.id.to_s], json.keys
      assert_equal ["見積"], json[@sales.id.to_s].pluck("name")
      assert_not json[@sales.id.to_s].first["has_children"]
    end
  end

  describe "共有されたアイテム" do
    test "親が見えず自分に共有されたものを並べる" do
      TenantContext.switch(tenant: @tenant) { grant(@review, @member, :viewer) }
      login(@member_user)
      get files_api_shared_path

      assert_equal ["評価.xlsx"], json["entries"].pluck("name")
    end

    test "共有されたフォルダを開くと、パンくずは共有されたアイテムから始まる" do
      shared = TenantContext.switch(tenant: @tenant) do
        node(:folder, "面談", @hr).tap { |folder| grant(folder, @member, :viewer) }
      end
      login(@member_user)
      get files_api_folder_path(shared)

      assert_response :success
      assert json["via_shared"]
      assert_empty json["breadcrumbs"], "閲覧できない人事・ルートは出さない"
      assert_equal "shared_drive", json["section"]
    end
  end

  describe "ゴミ箱" do
    test "親フォルダの編集者には削除したものが、削除した人と一緒に出る" do
      TenantContext.switch(tenant: @tenant) do
        grant(@sales, @member, :editor)
        trashed = node(:file, "古い見積.pdf", @sales, byte_size: 2048)
        trashed.update!(deleted_at: Time.current, deleted_root_id: trashed.id, deleted_by: @owner)
      end
      login(@member_user)
      get files_api_trash_path

      assert_equal 1, json["entries"].size
      assert_equal(
        { "name" => "古い見積.pdf", "deleted_by" => "管理者さん", "byte_size" => 2048 },
        json["entries"].first.slice("name", "deleted_by", "byte_size"),
      )
    end

    test "閲覧者には出ない" do
      TenantContext.switch(tenant: @tenant) do
        trashed = node(:file, "古い見積.pdf", @sales)
        trashed.update!(deleted_at: Time.current, deleted_root_id: trashed.id)
      end
      login(@member_user)
      get files_api_trash_path

      assert_empty json["entries"]
    end
  end

  describe "ファイル管理を利用しない" do
    setup do
      TenantContext.switch(tenant: @tenant) { @tenant.files_setting.update!(enabled: false) }
    end

    test "メニューに「ファイル」を出さず、画面も API も 404" do
      login(@owner_user)

      get top_page_path
      assert_select "dialog[data-drawer] a[href=?]", files_root_path, 0

      [files_root_path, files_folder_path(@sales), files_my_drive_path, files_trash_path, files_api_tree_path].each do |path|
        get path
        assert_response :not_found
      end
    end
  end

  private

  def json
    response.parsed_body
  end

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
