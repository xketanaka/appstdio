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

  describe "アップロード" do
    setup do
      TenantContext.switch(tenant: @tenant) { grant(@sales, @member, :editor) }
      login(@member_user)
    end

    def prepare(name: "提案書.pdf", byte_size: 12, parent: @sales)
      post prepare_upload_files_api_nodes_path, params: {
        parent_id: parent.id, blob: { filename: name, byte_size:, checksum: "AAAAAAAAAAAAAAAAAAAAAA==", content_type: "application/pdf" },
      }, as: :json
    end

    test "1段目は確かめてから、中身を送る先を返す" do
      prepare

      assert_response :success
      assert json["signed_id"].present?
      assert_match %r{/rails/active_storage/disk/}, json.dig("direct_upload", "url")
    end

    test "1段目で、大きすぎる・同じ名前がある・容量が足りないを断る" do
      prepare(byte_size: Settings.files.max_upload_bytes + 1)
      assert_response :unprocessable_content
      assert_equal ["ファイルの大きさは 5 GB までです。"], json["errors"]

      prepare(name: "見積")
      assert_equal ["名前が同じフォルダの中のものと重複しています。"], json["errors"]

      TenantContext.switch(tenant: @tenant) { @tenant.files_setting.update!(storage_limit_bytes: 10) }
      prepare
      assert_equal ["ファイルを保存する容量の上限を超えるため、アップロードできません。"], json["errors"]
    end

    test "閲覧者は 403" do
      prepare(parent: @root)

      assert_response :forbidden
    end

    test "2段目で、中身の届いた blob をファイルとして登録する" do
      blob = uploaded_blob("提案の中身", "提案書.txt", by: @member)
      post upload_files_api_nodes_path, params: { parent_id: @sales.id, signed_blob_id: blob.signed_id }, as: :json

      assert_response :created
      get files_api_folder_path(@sales)
      assert_equal ["見積", "提案書.txt"], json["entries"].pluck("name")
      assert_equal blob.byte_size, json["entries"].last["byte_size"]
    end

    test "2段目で、中身が届いていない blob や、使い回しの blob は 404" do
      waiting = ActiveStorage::Blob.create_before_direct_upload!(
        filename: "a.txt", byte_size: 1, checksum: "AAAAAAAAAAAAAAAAAAAAAA==", content_type: "text/plain",
        metadata: { uploaded_by: @member.id },
      )
      post upload_files_api_nodes_path, params: { parent_id: @sales.id, signed_blob_id: waiting.signed_id }, as: :json
      assert_response :not_found

      blob = uploaded_blob("x", "b.txt", by: @member)
      post upload_files_api_nodes_path, params: { parent_id: @sales.id, signed_blob_id: blob.signed_id }, as: :json
      assert_response :created
      post upload_files_api_nodes_path, params: { parent_id: @estimates.id, signed_blob_id: blob.signed_id }, as: :json
      assert_response :not_found
    end

    test "2段目で容量が埋まっていたら断り、届いた中身を消す" do
      blob = uploaded_blob("提案の中身", "提案書.txt", by: @member)
      TenantContext.switch(tenant: @tenant) { @tenant.files_setting.update!(storage_limit_bytes: 1) }

      assert_enqueued_with(job: ActiveStorage::PurgeJob) do
        post upload_files_api_nodes_path, params: { parent_id: @sales.id, signed_blob_id: blob.signed_id }, as: :json
      end
      assert_response :unprocessable_content
      assert_equal ["ファイルを保存する容量の上限を超えるため、アップロードできません。"], json["errors"]
    end

    test "2段目で、ほかの人が上げた blob は 404。signed_id が漏れても横取りできない" do
      blob = uploaded_blob("所有者の中身", "提案書.txt", by: @owner)
      post upload_files_api_nodes_path, params: { parent_id: @sales.id, signed_blob_id: blob.signed_id }, as: :json

      assert_response :not_found
    end

    test "上げた人の記録は、中身を調べて付帯情報を書き足しても残る" do
      blob = uploaded_blob("提案の中身", "提案書.txt", by: @member)
      blob.analyze

      assert_equal @member.id, blob.reload.metadata["uploaded_by"]
      assert blob.analyzed?
    end

    test "Active Storage 標準のダイレクトアップロードの受け口は塞いである" do
      post "/rails/active_storage/direct_uploads", params: { blob: { filename: "a.txt", byte_size: 1 } }, as: :json

      assert_response :not_found
    end
  end

  describe "ダウンロード" do
    setup do
      @file = TenantContext.switch(tenant: @tenant) do
        blob = ActiveStorage::Blob.create_and_upload!(io: StringIO.new("評価の中身"), filename: "評価.txt")
        Files::Node.create_file!(parent: @sales, blob:, creator: @owner)
      end
    end

    test "閲覧できれば、期限付きの保存先の URL へ転送する" do
      login(@member_user)
      get download_files_api_node_path(@file)

      assert_response :redirect
      assert_match %r{/rails/active_storage/disk/.+/評価\.txt}, URI.decode_www_form_component(response.location)
      follow_redirect!
      assert_equal "評価の中身", response.body.force_encoding("UTF-8")
      assert_match(/attachment/, response.headers["Content-Disposition"])
    end

    test "閲覧できなければ 404" do
      TenantContext.switch(tenant: @tenant) { grant(@sales, @everyone, :none) }
      login(@member_user)
      get download_files_api_node_path(@file)

      assert_response :not_found
    end
  end

  describe "名前の変更・ゴミ箱・復元" do
    setup do
      TenantContext.switch(tenant: @tenant) { grant(@root, @member, :editor) }
      login(@member_user)
    end

    test "名前を変える。同じ名前があれば 422" do
      patch rename_files_api_node_path(@minutes), params: { name: "議事録.md" }, as: :json
      assert_response :no_content

      patch rename_files_api_node_path(@minutes), params: { name: "営業" }, as: :json
      assert_response :unprocessable_content
      assert_equal ["名前が同じフォルダの中のものと重複しています。"], json["errors"]
    end

    test "ゴミ箱へ入れると一覧から消えてゴミ箱に出て、復元で戻る" do
      post trash_files_api_nodes_path, params: { node_ids: [@sales.id, @minutes.id] }, as: :json
      assert_response :no_content
      get files_api_drives_shared_path
      assert_equal ["人事"], json["entries"].pluck("name")
      get files_api_folder_path(@estimates)
      assert_response :not_found, "配下も一緒にゴミ箱に入る"
      get files_api_trash_path
      assert_equal ["営業", "議事録.docx"], json["entries"].pluck("name").sort

      post restore_files_api_nodes_path, params: { node_ids: [@sales.id] }, as: :json
      assert_response :no_content
      get files_api_folder_path(@estimates)
      assert_response :success
    end

    test "ゴミ箱に出ていない配下は、それだけを復元できない" do
      post trash_files_api_nodes_path, params: { node_ids: [@sales.id] }, as: :json
      post restore_files_api_nodes_path, params: { node_ids: [@estimates.id] }, as: :json

      assert_response :not_found
    end

    test "完全に削除するとゴミ箱から消え、復元できない。ゴミ箱に無いものは消せない" do
      post purge_files_api_nodes_path, params: { node_ids: [@sales.id] }, as: :json
      assert_response :not_found

      post trash_files_api_nodes_path, params: { node_ids: [@sales.id] }, as: :json
      post purge_files_api_nodes_path, params: { node_ids: [@sales.id] }, as: :json
      assert_response :no_content
      get files_api_trash_path
      assert_empty json["entries"]
      post restore_files_api_nodes_path, params: { node_ids: [@sales.id] }, as: :json
      assert_response :not_found
    end

    test "完全削除も、親フォルダを編集できなければ 403" do
      TenantContext.switch(tenant: @tenant) do
        grant(@sales, @member, :viewer)
        Files::Node.trash!([@estimates], actor: @owner)
      end

      post purge_files_api_nodes_path, params: { node_ids: [@estimates.id] }, as: :json
      assert_response :forbidden
    end

    test "親フォルダを編集できなければ 403" do
      TenantContext.switch(tenant: @tenant) { grant(@sales, @member, :viewer) }

      post trash_files_api_nodes_path, params: { node_ids: [@estimates.id] }, as: :json
      assert_response :forbidden
      patch rename_files_api_node_path(@estimates), params: { name: "見積書" }, as: :json
      assert_response :forbidden
    end
  end

  describe "版" do
    setup do
      @file = TenantContext.switch(tenant: @tenant) do
        blob = ActiveStorage::Blob.create_and_upload!(io: StringIO.new("版1"), filename: "仕様.txt")
        Files::Node.create_file!(parent: @sales, blob:, creator: @owner)
      end
    end

    def upload_new_blob(by:)
      uploaded_blob("版2の中身", "仕様.txt", by:)
    end

    test "同じ名前でアップロードすると、そのファイルの新しい版になる" do
      TenantContext.switch(tenant: @tenant) { grant(@sales, @member, :editor) }
      login(@member_user)

      post prepare_upload_files_api_nodes_path, params: {
        parent_id: @sales.id, blob: { filename: "仕様.txt", byte_size: 10, checksum: "AAAAAAAAAAAAAAAAAAAAAA==", content_type: "text/plain" },
      }, as: :json
      assert_response :success

      post upload_files_api_nodes_path, params: { parent_id: @sales.id, signed_blob_id: upload_new_blob(by: @member).signed_id }, as: :json
      assert_response :created
      assert_equal({ "id" => @file.id, "name" => "仕様.txt", "version" => 2 }, json)
      get files_api_folder_path(@sales)
      assert_equal 1, json["entries"].count { it["name"] == "仕様.txt" }
    end

    test "同じ名前のファイルを編集できなければ、新しい版にせず断る" do
      TenantContext.switch(tenant: @tenant) do
        grant(@sales, @member, :editor)
        grant(@file, @member, :viewer)
      end
      login(@member_user)

      post prepare_upload_files_api_nodes_path, params: {
        parent_id: @sales.id, blob: { filename: "仕様.txt", byte_size: 10, checksum: "AAAAAAAAAAAAAAAAAAAAAA==", content_type: "text/plain" },
      }, as: :json
      assert_equal ["同じ名前の「仕様.txt」がありますが、新しい版を足す権限がありません。"], json["errors"]

      post upload_files_api_nodes_path, params: { parent_id: @sales.id, signed_blob_id: upload_new_blob(by: @member).signed_id }, as: :json
      assert_response :forbidden
    end

    test "版の一覧を新しい順に返し、古い版も落とせ、ラベルを付け、最新に戻せる" do
      login(@owner_user)
      post files_api_node_versions_path(@file), params: { signed_blob_id: upload_new_blob(by: @owner).signed_id }, as: :json
      assert_equal 2, json["version"]

      get files_api_node_versions_path(@file)
      assert json["can_edit"]
      assert_equal [[2, true], [1, false]], json["versions"].map { [it["number"], it["current"]] }
      first = json["versions"].last["id"]

      get download_files_api_node_version_path(@file, first)
      follow_redirect!
      assert_equal "版1", response.body.force_encoding("UTF-8")

      patch files_api_node_version_path(@file, first), params: { label: "承認版" }, as: :json
      assert_response :no_content

      post restore_files_api_node_version_path(@file, first), as: :json
      assert_equal 3, json["version"]
      get files_api_node_versions_path(@file)
      assert_equal [[3, nil], [2, nil], [1, "承認版"]], json["versions"].map { [it["number"], it["label"]] }
    end

    test "閲覧者は一覧を見られるが、版を足す・ラベルを変える・最新に戻すはできない" do
      login(@member_user)
      get files_api_node_versions_path(@file)
      assert_not json["can_edit"]
      version = json["versions"].first["id"]

      post files_api_node_versions_path(@file), params: { signed_blob_id: upload_new_blob(by: @member).signed_id }, as: :json
      assert_response :forbidden
      patch files_api_node_version_path(@file, version), params: { label: "x" }, as: :json
      assert_response :forbidden
      post restore_files_api_node_version_path(@file, version), as: :json
      assert_response :forbidden
    end

    test "閲覧できないファイルの版は 404" do
      TenantContext.switch(tenant: @tenant) { grant(@sales, @everyone, :none) }
      login(@member_user)
      get files_api_node_versions_path(@file)

      assert_response :not_found
    end
  end

  describe "共有設定" do
    setup do
      TenantContext.switch(tenant: @tenant) do
        @sales_group = Group.create!(tenant: @tenant, name: "営業部")
        grant(@sales, @member, :manager)
        grant(@estimates, @sales_group, :editor)
        grant(@estimates, @everyone, :none)
      end
    end

    test "継承した設定を継承元と一緒に、このフォルダの設定と分けて返す" do
      login(@member_user)
      get files_api_node_permissions_path(@estimates)

      assert_response :success
      inherited = json["inherited"].to_h { [it.dig("subject", "name"), it.slice("role", "cancelled")] }
      assert_equal({ "全員" => { "role" => "viewer", "cancelled" => true },
                     "一般さん" => { "role" => "manager", "cancelled" => false } }, inherited)
      assert_equal "営業", json["inherited"].find { it.dig("subject", "name") == "一般さん" }.dig("from", "label")
      assert_equal [["営業部", "editor"]], json["own"].map { [it.dig("subject", "name"), it["role"]] }
      assert_equal ["営業部"], json["own"].first.dig("subject", "path")
    end

    test "見えない上位のフォルダは、継承元の名前を返さない" do
      folder = TenantContext.switch(tenant: @tenant) do
        grant(@hr, @owner, :editor)
        node(:folder, "面談", @hr).tap { grant(it, @member, :manager) }
      end
      login(@member_user)
      get files_api_node_permissions_path(folder)

      assert_nil json["inherited"].find { it.dig("subject", "name") == "管理者さん" }["from"]
    end

    test "差分をまとめて反映する" do
      login(@member_user)
      patch files_api_node_permissions_path(@estimates), params: { changes: [
        { subject_type: "group", subject_id: @sales_group.id, role: "viewer" },
        { subject_type: "group", subject_id: @everyone.id, role: "" },
        { subject_type: "tenant_user", subject_id: @owner.id, role: "editor" },
      ] }, as: :json

      assert_response :no_content
      roles = TenantContext.switch(tenant: @tenant) { @estimates.permissions.map { [it.subject.id, it.role] } }
      assert_equal [[@sales_group.id, "viewer"], [@owner.id, "editor"]].sort, roles.sort
    end

    test "管理者が1人もいなくなる変更は 422 で、何も変えない" do
      login(@member_user)
      patch files_api_node_permissions_path(@sales), params: { changes: [
        { subject_type: "tenant_user", subject_id: @member.id, role: "editor" },
      ] }, as: :json

      assert_response :unprocessable_content
      assert_match "管理者が1人もいなくなります", json["errors"].first
      assert TenantContext.switch(tenant: @tenant) { @sales.permissions.find_by(tenant_user: @member).role_manager? }
    end

    test "利用停止中の人・グループには、そのことを返す" do
      TenantContext.switch(tenant: @tenant) do
        @sales_group.suspend!(by: @owner)
        @owner.update!(status: :suspended)
        grant(@estimates, @owner, :viewer)
      end
      login(@member_user)
      get files_api_node_permissions_path(@estimates)

      assert_equal({ "営業部" => true, "管理者さん" => true }, json["own"].to_h { [it.dig("subject", "name"), it.dig("subject", "suspended")] })
      assert_not json["inherited"].first.dig("subject", "suspended")
    end

    test "利用停止中のグループは新しく加えられない" do
      TenantContext.switch(tenant: @tenant) { @sales_group.suspend!(by: @owner) }
      login(@member_user)
      patch files_api_node_permissions_path(@sales), params: { changes: [
        { subject_type: "group", subject_id: @sales_group.id, role: "viewer" },
      ] }, as: :json

      assert_response :unprocessable_content
      assert_match "「営業部」", json["errors"].first
    end

    test "編集者には 403、見えない人には 404" do
      TenantContext.switch(tenant: @tenant) { grant(@sales, @owner, :editor) }
      login(@owner_user)
      get files_api_node_permissions_path(@sales)
      assert_response :forbidden
      patch files_api_node_permissions_path(@sales), params: { changes: [] }, as: :json
      assert_response :forbidden

      get files_api_node_permissions_path(@hr)
      assert_response :not_found
    end

    test "項目とフォルダに、共有設定を変えられるかを返す" do
      login(@member_user)
      get files_api_folder_path(@root)
      assert_equal [true, false], json["entries"].select { it["name"].in?(%w[営業 議事録.docx]) }.sort_by { it["kind"] }
        .reverse.map { it["manageable"] }

      get files_api_folder_path(@sales)
      assert json["can_manage"]
    end

    test "加える相手の候補は、有効なグループと有効・招待中の人" do
      TenantContext.switch(tenant: @tenant) do
        Group.create!(tenant: @tenant, name: "営業2部").suspend!(by: @owner)
        @owner.update!(status: :suspended)
      end
      login(@member_user)
      get files_api_share_candidates_path, params: { q: "営業" }

      assert_equal ["営業部"], json["candidates"].pluck("name")
      assert_equal [["営業部"]], json["candidates"].pluck("path")

      get files_api_share_candidates_path, params: { q: "" }
      names = json["candidates"].pluck("name")
      assert_includes names, "全員"
      assert_includes names, "一般さん"
      assert_not_includes names, "管理者さん"
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

  # ダイレクトアップロードの1段目で作られる blob と同じく、上げた人を付帯情報に持たせる
  def uploaded_blob(content, filename, by:)
    ActiveStorage::Blob.create_and_upload!(io: StringIO.new(content), filename:, metadata: { uploaded_by: by.id })
  end

  def grant(node, subject, role)
    subject_key = subject.is_a?(Group) ? :group : :tenant_user
    Files::Permission.create!(tenant: @tenant, node: node, subject_key => subject, role: role)
  end
end
