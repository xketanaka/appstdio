require "test_helper"

class ProfileTest < ActionDispatch::IntegrationTest
  PASSWORD = "password1234".freeze

  setup do
    @tenant = Tenant.create!(name: "テナントA")
    @other_tenant = Tenant.create!(name: "テナントB")
    @user = User.create!(email: "a@example.com", password: PASSWORD)
    @membership = TenantContext.switch(tenant: @tenant) do
      TenantUser.create!(
        tenant: @tenant, user: @user, display_name: "Aさん", role: :owner, status: :active,
      )
    end
    login
  end

  teardown do
    TenantContext.clear
  end

  test "アカウントメニューから個人設定・テナント切り替え・ログアウトへ行ける" do
    get top_page_path

    assert_select "details[data-dropdown]" do
      assert_select "a[href=?]", profile_path
      assert_select "a[href=?]", select_tenant_path
      assert_select "form[action=?]", logout_path
    end
  end

  test "表示名を変更できる" do
    patch profile_path, params: { tenant_user: { display_name: "新しい名前" } }
    assert_redirected_to profile_path

    TenantContext.switch(tenant: @tenant) do
      assert_equal "新しい名前", @membership.reload.display_name
    end

    follow_redirect!
    assert_select "[role=status]", text: /更新しました/
  end

  test "表示名を空にはできない" do
    patch profile_path, params: { tenant_user: { display_name: "" } }

    assert_response :unprocessable_entity
    assert_select "[role=alert]"
    TenantContext.switch(tenant: @tenant) do
      assert_equal "Aさん", @membership.reload.display_name
    end
  end

  test "未ログインでは個人設定を開けない" do
    delete logout_path

    get profile_path
    assert_redirected_to login_path
  end

  private

  def login
    post login_path, params: { email: @user.email, password: PASSWORD }
    follow_redirect!   # 所属が1件なのでテナントは自動で選択される
    follow_redirect!
  end
end
