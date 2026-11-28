require "test_helper"

# 通常の bin/rails test では動かない。bin/rails test:ops で実行する
class OperatorPasswordResetsTest < ActionDispatch::IntegrationTest
  PASSWORD = "password1234".freeze

  setup do
    skip("運営者画面のテストは bin/rails test:ops で実行する") unless Rails.configuration.x.ops_console

    @operator = Operator.create!(email: "operator@example.com", password: PASSWORD, display_name: "運用担当", status: :active)
    ActionMailer::Base.deliveries.clear
  end

  # 再設定のメールを送り、メールの URL を返す
  def request_reset(email = @operator.email)
    perform_enqueued_jobs { post ops_password_resets_path, params: { email: } }
    ActionMailer::Base.deliveries.last&.text_part&.body&.decoded.to_s[%r{https?://\S+/ops/password_resets/\S+/edit}]
  end

  test "ログインの画面から、OPS_URL を元にした URL で新しいパスワードを決め、そのままログインする。他の端末のログインは切れる" do
    other_device = open_session
    other_device.post ops_login_path, params: { email: @operator.email, password: PASSWORD }
    other_device.get ops_root_path
    other_device.assert_response :success

    get ops_login_path
    assert_select "a[href=?]", new_ops_password_reset_path

    url = request_reset
    assert_redirected_to ops_login_path
    mail = ActionMailer::Base.deliveries.last
    assert_equal ["operator@example.com"], mail.to
    assert_equal "AppStdio 運営者画面 のパスワードの再設定", mail.subject
    # リクエストのホスト名（www.example.com）ではなく、設定の OPS_URL から作る
    assert url.start_with?("http://ops.example.com/ops/password_resets/"), url
    path = URI(url).path.delete_suffix("/edit")

    get "#{path}/edit"
    assert_select "#password-reset dd", text: "operator@example.com"

    patch path, params: { password: "", password_confirmation: "" }
    assert_response :unprocessable_entity
    patch path, params: { password: "newpassword1", password_confirmation: "different1" }
    assert_response :unprocessable_entity
    assert @operator.reload.authenticate(PASSWORD)

    patch path, params: { password: "newpassword1", password_confirmation: "newpassword1" }
    assert_redirected_to ops_root_path
    assert @operator.reload.authenticate("newpassword1")
    get ops_root_path
    assert_response :success
    other_device.get ops_root_path
    other_device.assert_redirected_to ops_login_path

    # パスワードを変えたあとは同じ URL は使えない
    get "#{path}/edit"
    assert_response :not_found
    assert_select "#password-reset-invalid"
  end

  test "登録の無いメールアドレス・停止中・招待中の運営者には送らず、同じ案内を出す" do
    Operator.create!(email: "suspended@example.com", password: PASSWORD, display_name: "停止", status: :suspended)
    Operator.create!(email: "invited@example.com", password: PASSWORD, display_name: "招待", status: :invited)

    %w[nobody@example.com suspended@example.com invited@example.com].each do |email|
      assert_nil request_reset(email)
      assert_redirected_to ops_login_path
      follow_redirect!
      assert_select "[role=status]", text: /登録されていれば/
    end
  end

  test "ログイン前に見ようとしたページがあれば、パスワードを決めたあとそこへ戻る" do
    get ops_tenants_path
    assert_redirected_to ops_login_path

    path = URI(request_reset).path.delete_suffix("/edit")
    patch path, params: { password: "newpassword1", password_confirmation: "newpassword1" }
    assert_redirected_to ops_tenants_path
  end

  test "期限（30分）を過ぎた URL と、送ったあとに停止した運営者の URL は使えない" do
    path = URI(request_reset).path

    travel 31.minutes do
      get path
      assert_response :not_found
    end

    get path
    assert_response :success
    @operator.update!(status: :suspended)
    get path
    assert_response :not_found
  end
end
