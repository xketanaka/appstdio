require "test_helper"

# 通常の bin/rails test では動かない。bin/rails test:ops で実行する
class OperatorPasswordsTest < ActionDispatch::IntegrationTest
  PASSWORD = "password1234".freeze

  setup do
    skip("運営者画面のテストは bin/rails test:ops で実行する") unless Rails.configuration.x.ops_console

    @operator = Operator.create!(email: "operator@example.com", password: PASSWORD, display_name: "運用担当", status: :active)
  end

  test "アカウントメニューから、今のパスワードを入れて変える。この端末はログインしたまま、ほかの端末は切れる" do
    other_device = open_session
    other_device.post ops_login_path, params: { email: @operator.email, password: PASSWORD }
    post ops_login_path, params: { email: @operator.email, password: PASSWORD }

    get ops_root_path
    assert_select "details[data-dropdown] a[href=?]", edit_ops_password_path
    get edit_ops_password_path
    assert_select "#password-form input[name=current_password]"

    patch ops_password_path, params: { current_password: "wrong-password", password: "newpassword1", password_confirmation: "newpassword1" }
    assert_response :unprocessable_entity
    assert_select "[role=alert]", text: /今のパスワード/
    patch ops_password_path, params: { current_password: PASSWORD, password: "", password_confirmation: "" }
    assert_response :unprocessable_entity
    patch ops_password_path, params: { current_password: PASSWORD, password: "newpassword1", password_confirmation: "different1" }
    assert_response :unprocessable_entity
    assert @operator.reload.authenticate(PASSWORD)

    patch ops_password_path, params: { current_password: PASSWORD, password: "newpassword1", password_confirmation: "newpassword1" }
    assert_redirected_to ops_root_path
    assert @operator.reload.authenticate("newpassword1")
    get ops_root_path
    assert_response :success
    other_device.get ops_root_path
    other_device.assert_redirected_to ops_login_path
  end

  test "ログインしていなければ開けない" do
    get edit_ops_password_path
    assert_redirected_to ops_login_path
  end
end
