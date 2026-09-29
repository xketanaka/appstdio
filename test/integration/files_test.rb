require "test_helper"

class FilesTest < ActionDispatch::IntegrationTest
  PASSWORD = "password1234".freeze

  setup do
    @tenant = Tenant.create!(name: "テナントA")
    @user = User.create!(email: "a@example.com", password: PASSWORD)
    TenantContext.switch(tenant: @tenant) do
      TenantUser.create!(
        tenant: @tenant, user: @user, display_name: "Aさん", role: :owner, status: :active,
      )
    end
    post login_path, params: { email: @user.email, password: PASSWORD }
    follow_redirect!
    follow_redirect!
  end

  teardown do
    TenantContext.clear
  end

  test "ドライブの一覧を表示する" do
    get files_root_path
    assert_response :success

    assert_select "aside details", 4
    assert_select "aside details[open]", 1
    assert_select "aside", text: /組織共有ドライブ.*共有されたアイテム.*マイドライブ.*ゴミ箱/m

    assert_select "#file-list thead th", 5
    assert_select "#file-list tbody tr", 3
    assert_select "#file-list tbody tr:first-child td", text: "-"   # フォルダはサイズなし
  end

  test "メニューの「ファイル」から開ける" do
    get top_page_path
    assert_select "dialog[data-drawer] a[href=?]", files_root_path
  end

  test "テナント未選択でアクセスすると、選択後に元のページへ戻る" do
    other = Tenant.create!(name: "テナントB")
    TenantContext.switch(tenant: other) do
      TenantUser.create!(tenant: other, user: @user, display_name: "Aさん", status: :active)
    end
    delete logout_path
    post login_path, params: { email: @user.email, password: PASSWORD }

    get files_root_path
    assert_redirected_to select_tenant_path

    post select_tenant_path, params: { tenant_id: @tenant.id }
    assert_redirected_to files_root_path
  end

  test "未ログインでは開けない" do
    delete logout_path

    get files_root_path
    assert_redirected_to login_path
  end
end
