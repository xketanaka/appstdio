require "test_helper"

class MainMenuTest < ActionDispatch::IntegrationTest
  PASSWORD = "password1234".freeze

  setup do
    @tenant = Tenant.create!(name: "テナントA")
    @user = User.create!(email: "a@example.com", password: PASSWORD)
    TenantContext.switch(tenant: @tenant) do
      TenantUser.create!(
        tenant: @tenant, user: @user, display_name: "Aさん", role: :owner, status: :active,
      )
    end
  end

  teardown do
    TenantContext.clear
  end

  test "ログイン後はメニューを開くボタンとスライドメニューが出る" do
    login
    get top_page_path

    assert_select "button[data-drawer-open]"
    assert_select "dialog[data-drawer]" do
      assert_select "nav span[aria-disabled=true]", 3
      assert_select "nav", text: /ファイル/
      assert_select "nav", text: /ページ/
      assert_select "nav", text: /チャット/
    end
  end

  test "未ログインの画面にはメニューを出さない" do
    get login_path

    assert_response :success
    assert_select "button[data-drawer-open]", 0
    assert_select "dialog[data-drawer]", 0
  end

  private

  def login
    post login_path, params: { email: @user.email, password: PASSWORD }
    follow_redirect!
    follow_redirect!
  end
end
