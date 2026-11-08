require "test_helper"

class AvatarsTest < ActionDispatch::IntegrationTest
  PASSWORD = "password1234".freeze

  setup do
    @tenant = Tenant.setup!(name: "テナントA")
    @other_tenant = Tenant.setup!(name: "テナントB")
    @dir = Dir.mktmpdir
    TenantContext.switch(tenant: @tenant) do
      @admin = TenantUser.create!(tenant: @tenant, user: User.create!(email: "admin@example.com", password: PASSWORD),
        display_name: "管理者さん", role: :admin, status: :active)
      @sato = TenantUser.create!(tenant: @tenant, user: User.create!(email: "sato@example.com", password: PASSWORD),
        display_name: "佐藤さん", role: :member, status: :active)
    end
    TenantContext.switch(tenant: @other_tenant) do
      @outsider = TenantUser.create!(tenant: @other_tenant, user: User.create!(email: "b@example.com", password: PASSWORD),
        display_name: "Bさん", role: :owner, status: :active)
      @outsider.replace_avatar(image_path)
    end
  end

  teardown do
    TenantContext.clear
    FileUtils.remove_entry(@dir)
  end

  # 左半分が黒、右半分が白の横長の画像
  def image_path
    image = Vips::Image.black(200, 200).join(Vips::Image.black(200, 200) + 255, :horizontal)
    File.join(@dir, "photo.png").tap { image.write_to_file(it) }
  end

  def upload(path = image_path, type = "image/png")
    Rack::Test::UploadedFile.new(path, type)
  end

  def avatar_of(tenant_user)
    TenantContext.switch(tenant: @tenant) { tenant_user.reload.avatar }
  end

  test "個人設定で、選んだ範囲を切り抜いてアバターにし、画面右上にも出す" do
    login(@sato)

    patch profile_avatar_path, params: { avatar: upload, crop: { x: "250", y: "0", size: "150" } }
    assert_redirected_to profile_path

    avatar = avatar_of(@sato)
    assert_equal "image/webp", avatar.blob.content_type
    image = Vips::Image.new_from_buffer(avatar.blob.download, "")
    assert_equal [AvatarImage::SIZE, AvatarImage::SIZE], [image.width, image.height]
    assert_operator image.avg, :>, 245

    follow_redirect!
    src = avatar_path(@sato, avatar.blob_id)
    assert_select "details[data-dropdown] summary img[src=?]", src
    assert_select "#avatar img[src=?]", src
  end

  test "範囲が送られなければ中央を切り抜く" do
    login(@sato)

    patch profile_avatar_path, params: { avatar: upload }

    image = Vips::Image.new_from_buffer(avatar_of(@sato).blob.download, "")
    assert_operator image.crop(0, 0, 10, 10).avg, :<, 10
    assert_operator image.crop(AvatarImage::SIZE - 10, 0, 10, 10).avg, :>, 245
  end

  test "範囲が空・形の違うもので届いたら、中央を切り抜く" do
    login(@sato)

    [{ x: "", y: "", size: "" }, "foo", { x: ["1"], y: "0", size: "100" }].each do |crop|
      patch profile_avatar_path, params: { avatar: upload, crop: }
      assert_redirected_to profile_path

      image = Vips::Image.new_from_buffer(avatar_of(@sato).blob.download, "")
      assert_operator image.crop(0, 0, 10, 10).avg, :<, 10
      assert_operator image.crop(AvatarImage::SIZE - 10, 0, 10, 10).avg, :>, 245
    end
  end

  test "画像でないものは受け付けず、前のアバターを残す" do
    TenantContext.switch(tenant: @tenant) { @sato.replace_avatar(image_path) }
    blob_id = avatar_of(@sato).blob_id
    login(@sato)

    svg = File.join(@dir, "a.svg").tap { File.write(it, %(<svg xmlns="http://www.w3.org/2000/svg"/>)) }
    patch profile_avatar_path, params: { avatar: upload(svg, "image/png") }

    assert_response :unprocessable_entity
    assert_select "[role=alert]", text: /PNG・JPEG・GIF・WebP/
    assert_equal blob_id, avatar_of(@sato).blob_id
  end

  test "差し替えると URL が変わり、本人が削除すると人の絵に戻る" do
    TenantContext.switch(tenant: @tenant) { @sato.replace_avatar(image_path) }
    old_src = avatar_path(@sato, avatar_of(@sato).blob_id)
    login(@sato)

    patch profile_avatar_path, params: { avatar: upload }
    assert_not_equal old_src, avatar_path(@sato, avatar_of(@sato).blob_id)
    get old_src
    assert_response :not_found

    delete profile_avatar_path
    assert_redirected_to profile_path
    assert_not avatar_of(@sato).attached?
    follow_redirect!
    assert_select "#avatar img[src]", 0
    assert_select "#remove-avatar", 0
  end

  test "同じテナントの人は画像を見られ、ブラウザに長くキャッシュさせる" do
    TenantContext.switch(tenant: @tenant) { @sato.replace_avatar(image_path) }
    login(@admin)

    get avatar_path(@sato, avatar_of(@sato).blob_id)

    assert_response :success
    assert_equal "image/webp", response.media_type
    assert_includes response.headers["Cache-Control"], "private"
    assert_includes response.headers["Cache-Control"], "immutable"
  end

  test "他のテナントの人の画像は見られない" do
    blob_id = TenantContext.switch(tenant: @other_tenant) { @outsider.avatar.blob_id }
    login(@admin)

    get avatar_path(@outsider, blob_id)

    assert_response :not_found
  end

  test "ログインしていなければ画像は見られない" do
    TenantContext.switch(tenant: @tenant) { @sato.replace_avatar(image_path) }

    get avatar_path(@sato, avatar_of(@sato).blob_id)

    assert_redirected_to login_path
  end

  test "管理者は利用者の編集の画面からアバターを削除できる" do
    TenantContext.switch(tenant: @tenant) { @sato.replace_avatar(image_path) }
    login(@admin)

    get edit_management_user_path(@sato)
    assert_select "#user-header img[src=?]", avatar_path(@sato, avatar_of(@sato).blob_id)

    delete management_user_avatar_path(@sato)
    assert_redirected_to edit_management_user_path(@sato)
    assert_not avatar_of(@sato).attached?
    follow_redirect!
    assert_select "#remove-avatar", 0
  end

  test "メンバーは他の人のアバターを削除できない" do
    TenantContext.switch(tenant: @tenant) { @admin.replace_avatar(image_path) }
    login(@sato)

    delete management_user_avatar_path(@admin)

    assert_response :not_found
    assert avatar_of(@admin).attached?
  end

  test "利用者の一覧・共有の相手の候補にアバターを出す" do
    TenantContext.switch(tenant: @tenant) { @sato.replace_avatar(image_path) }
    src = avatar_path(@sato, avatar_of(@sato).blob_id)
    login(@admin)

    get management_users_path
    assert_select "#user-list tr", text: /佐藤さん/ do
      assert_select "img[src=?]", src
    end

    get files_api_share_candidates_path, params: { q: "さん" }
    candidates = response.parsed_body["candidates"].to_h { [it["name"], it["avatar_url"]] }
    assert_equal({ "管理者さん" => nil, "佐藤さん" => src }, candidates.slice("管理者さん", "佐藤さん"))
  end

  private

  def login(tenant_user)
    post login_path, params: { email: tenant_user.user.email, password: PASSWORD }
    follow_redirect!
    follow_redirect!
  end
end
