require "test_helper"

class SiteHeaderTest < ActionDispatch::IntegrationTest
  PASSWORD = "password1234".freeze

  setup do
    @tenant = Tenant.setup!(name: "テナントA")
    @user = User.create!(email: "a@example.com", password: PASSWORD)
    TenantContext.switch(tenant: @tenant) do
      TenantUser.create!(tenant: @tenant, user: @user, display_name: "Aさん", role: :owner, status: :active)
    end
  end

  teardown do
    TenantContext.clear
  end

  test "組織設定が未設定なら既定のタイトルと色で出す" do
    login
    get top_page_path

    assert_select "title", text: "AppStdio - ホーム"
    assert_select "#site-header[style]", 0
    # ロゴが無ければ、ロゴの位置にタイトルの1文字目の印を出す
    assert_select "#site-title", text: /\AA\s*AppStdio\z/
    assert_select "#site-title img", 0
  end

  test "タイトルラベルとタイトルカラーを反映する" do
    update_setting(title_label: "サンプル株式会社", title_color: "#1e40af")
    login
    get top_page_path

    assert_select "title", text: "AppStdio | サンプル株式会社 - ホーム"
    assert_select "#site-header[style=?]", "background-color: #1e40af"
    assert_select "#site-title", text: /\Aサ\s*サンプル株式会社\z/
  end

  test "ロゴがあれば印の代わりにラベルの左に並べ、ラベルが空ならロゴだけにする" do
    update_setting(title_label: "サンプル株式会社", logo: png)
    login
    get top_page_path
    assert_select "#site-title img[alt=?]", "サンプル株式会社"
    assert_select "#site-title", text: /\Aサンプル株式会社\z/

    update_setting(title_label: nil)
    get top_page_path
    assert_select "#site-title img"
    assert_select "#site-title span", 0
  end

  test "ロゴは画面を移るたびに読み直さないよう、同じ URL で長くキャッシュさせる" do
    update_setting(logo: png)
    login

    get top_page_path
    src = css_select("#site-title img").first["src"]
    get management_users_path
    assert_equal src, css_select("#site-title img").first["src"]

    get src
    assert_response :success
    assert_match(/public/, response.headers["Cache-Control"])
    assert_match(/max-age=\d{6,}/, response.headers["Cache-Control"])
  end

  test "画面の枠は body に直接並べず、画面に固定した入れ物の中に組む" do
    login
    get top_page_path

    assert_select "body > #app-shell > header#site-header"
    assert_select "body > #app-shell main"
  end

  test "テナントを選ぶ前の画面は既定のまま" do
    update_setting(title_label: "サンプル株式会社")
    get login_path

    assert_select "title", text: "AppStdio - ログイン"
    assert_select "#site-title", text: /\AA\s*AppStdio\z/
  end

  private

  def login
    post login_path, params: { email: @user.email, password: PASSWORD }
    follow_redirect!
    follow_redirect!
  end

  def update_setting(**attributes)
    TenantContext.switch(tenant: @tenant) { @tenant.setting.update!(**attributes) }
  end

  def png
    { io: StringIO.new("png"), filename: "logo.png", content_type: "image/png" }
  end
end
