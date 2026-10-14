require "test_helper"

class TenantSettingsTest < ActionDispatch::IntegrationTest
  PASSWORD = "password1234".freeze

  setup do
    @tenant = Tenant.setup!(name: "テナントA")
    @user = User.create!(email: "owner@example.com", password: PASSWORD)
    TenantContext.switch(tenant: @tenant) do
      TenantUser.create!(tenant: @tenant, user: @user, display_name: "オーナーさん", role: :owner, status: :active)
    end
    post login_path, params: { email: @user.email, password: PASSWORD }
    follow_redirect!
    follow_redirect!
  end

  teardown do
    TenantContext.clear
  end

  test "未設定の項目は既定の表示であることを示し、編集ボタンを置く" do
    get management_tenant_setting_path
    assert_response :success

    assert_select "#tenant-appearance", text: /未設定（AppStdio を表示）/
    assert_select "#tenant-appearance", text: /未設定（既定の色）/
    assert_select "#tenant-features", text: /利用する/
    assert_select "#edit-tenant-setting[href=?]", edit_management_tenant_setting_path
  end

  test "タイトルラベル・タイトルカラー・ロゴを保存する" do
    patch management_tenant_setting_path, params: {
      tenant_setting: { title_label: "サンプル株式会社", title_color: "#1E40AF", logo: logo_file },
      files_enabled: "1",
    }
    assert_redirected_to management_tenant_setting_path

    follow_redirect!
    assert_select "[role=status]", text: /保存しました/
    assert_select "#tenant-appearance", text: /サンプル株式会社/
    assert_select "#tenant-appearance", text: /#1e40af/
    assert_select "#tenant-appearance img"
    assert_select "#site-title", text: "サンプル株式会社"
  end

  test "既定の色を使うにすると、送られた色を捨てて未設定に戻す" do
    update_setting(title_color: "#1e40af")

    patch management_tenant_setting_path, params: {
      tenant_setting: { title_color: "#1e40af" }, use_default_color: "1", files_enabled: "1",
    }

    assert_nil setting.title_color
  end

  test "ロゴを削除する" do
    update_setting(logo: { io: StringIO.new("png"), filename: "logo.png", content_type: "image/png" })

    patch management_tenant_setting_path, params: { tenant_setting: { title_label: "" }, remove_logo: "1", files_enabled: "1" }

    assert_not_predicate setting.logo, :attached?
  end

  test "ロゴの形式が不正なら保存せず、ファイル管理の設定も変えない" do
    patch management_tenant_setting_path, params: {
      tenant_setting: { title_label: "サンプル株式会社",
                        logo: Rack::Test::UploadedFile.new(StringIO.new("<svg/>"), "image/svg+xml", original_filename: "logo.svg") },
    }

    assert_response :unprocessable_entity
    assert_select "[role=alert]", text: /PNG・JPEG・GIF・WebP/
    assert_nil setting.title_label
    assert_predicate files_setting, :enabled?
    # 保存していない値はヘッダーに出さない
    assert_select "#site-title", text: /\AA\s*AppStdio\z/
  end

  test "ファイル管理を利用しないにする" do
    patch management_tenant_setting_path, params: { tenant_setting: { title_label: "" } }

    assert_not_predicate files_setting, :enabled?
    follow_redirect!
    assert_select "#tenant-features", text: /利用しない/
  end

  private

  # RLS があるので、読むのも書くのもテナントのコンテキストの中で行う
  def setting
    TenantContext.switch(tenant: @tenant) { TenantSetting.find_by!(tenant: @tenant) }
  end

  def files_setting
    TenantContext.switch(tenant: @tenant) { Files::Setting.find_by!(tenant: @tenant) }
  end

  def update_setting(**attributes)
    TenantContext.switch(tenant: @tenant) { setting.update!(**attributes) }
  end

  def logo_file
    Rack::Test::UploadedFile.new(StringIO.new("png"), "image/png", original_filename: "logo.png")
  end
end
