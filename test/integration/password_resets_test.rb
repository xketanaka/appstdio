require "test_helper"

class PasswordResetsTest < ActionDispatch::IntegrationTest
  PASSWORD = "password1234".freeze

  setup do
    @tenant = Tenant.setup!(name: "テナントA")
    @user = User.create!(email: "a@example.com", password: PASSWORD, last_signed_in_at: 1.day.ago)
    TenantContext.switch(tenant: @tenant) do
      TenantUser.create!(tenant: @tenant, user: @user, display_name: "Aさん", role: :owner, status: :active)
    end
    ActionMailer::Base.deliveries.clear
  end

  teardown do
    TenantContext.clear
  end

  # 再設定のメールを送り、メールの URL のトークンを返す
  def request_reset(email = @user.email)
    perform_enqueued_jobs { post password_resets_path, params: { email: } }
    ActionMailer::Base.deliveries.last.text_part.body.decoded[%r{https?://\S+/password_resets/(\S+)/edit}, 1]
  end

  test "ログインの画面から、メールの URL で新しいパスワードを決め、そのままログインする" do
    get login_path
    assert_select "a[href=?]", new_password_reset_path

    token = request_reset
    assert_redirected_to login_path
    mail = ActionMailer::Base.deliveries.last
    assert_equal ["a@example.com"], mail.to
    assert_equal "AppStdio のパスワードの再設定", mail.subject

    get edit_password_reset_path(token)
    assert_select "#password-reset dd", text: "a@example.com"

    # 確認が合わない・空なら変えない
    patch password_reset_path(token), params: { password: "newpassword1", password_confirmation: "different1" }
    assert_response :unprocessable_entity
    assert_select "[role=alert]", text: /パスワード（確認）/
    patch password_reset_path(token), params: { password: "", password_confirmation: "" }
    assert_response :unprocessable_entity
    assert @user.reload.authenticate(PASSWORD)

    patch password_reset_path(token), params: { password: "newpassword1", password_confirmation: "newpassword1" }
    assert_redirected_to select_tenant_path
    assert_equal @user.id, session[:current_user_id]
    follow_redirect!
    follow_redirect!
    assert_select "[role=status]", text: "パスワードを変更しました。"
    assert @user.reload.authenticate("newpassword1")
    assert @user.email_verified?

    # パスワードを変えたあとは同じ URL は使えない
    delete logout_path
    get edit_password_reset_path(token)
    assert_response :not_found
    assert_select "#password-reset-invalid"
  end

  test "登録の無いメールアドレスでも同じ案内を出し、メールは送らない" do
    perform_enqueued_jobs { post password_resets_path, params: { email: "nobody@example.com" } }
    assert_redirected_to login_path
    follow_redirect!
    assert_select "[role=status]", text: /登録されていれば/
    assert_empty ActionMailer::Base.deliveries
  end

  test "URL は30分で使えなくなる" do
    token = request_reset

    travel 29.minutes do
      get edit_password_reset_path(token)
      assert_response :success
    end
    travel 31.minutes do
      get edit_password_reset_path(token)
      assert_response :not_found
      patch password_reset_path(token), params: { password: "newpassword1", password_confirmation: "newpassword1" }
      assert_response :not_found
    end
    assert @user.reload.authenticate(PASSWORD)
  end

  test "改ざんした URL は使えない" do
    token = request_reset

    get edit_password_reset_path(token.sub(/.\z/) { it == "A" ? "B" : "A" })
    assert_response :not_found
    get edit_password_reset_path("foo")
    assert_response :not_found
  end
end
