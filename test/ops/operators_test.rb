require "test_helper"

# 通常の bin/rails test では動かない。bin/rails test:ops で実行する
class OperatorsTest < ActionDispatch::IntegrationTest
  PASSWORD = "password1234".freeze

  setup do
    skip("運営者画面のテストは bin/rails test:ops で実行する") unless Rails.configuration.x.ops_console

    @operator = Operator.create!(email: "operator@example.com", password: PASSWORD, display_name: "運用担当", status: :active)
    ActionMailer::Base.deliveries.clear
  end

  def login(email = @operator.email, password = PASSWORD)
    post ops_login_path, params: { email:, password: }
  end

  # 運営者を追加して招待メールを送り、メールの URL を返す
  def invite(email = "new@example.com", display_name: "新しい人")
    perform_enqueued_jobs do
      post ops_operators_path, params: { operator: { email:, display_name: } }
    end
    ActionMailer::Base.deliveries.last.text_part.body.decoded[%r{https?://\S+/ops/invitations/\S+}]
  end

  test "メニューの運営者から一覧を開き、追加すると招待メールを送り、本人が URL でパスワードを決めるとログインして有効になる" do
    login
    get ops_root_path
    assert_select "a[href=?]", ops_operators_path
    get ops_operators_path
    assert_select "#operator-list tbody tr", 1

    url = invite
    assert_redirected_to ops_operators_path
    mail = ActionMailer::Base.deliveries.last
    assert_equal ["new@example.com"], mail.to
    assert_equal "AppStdio 運営者画面 に招待されました", mail.subject
    assert_includes mail.text_part.body.decoded, "運用担当さんから"
    # リクエストのホスト名ではなく、設定の OPS_URL から作る
    assert url.start_with?("http://ops.example.com/ops/invitations/"), url
    invited = Operator.find_by!(email: "new@example.com")
    assert invited.invited?
    follow_redirect!
    assert_select "#operator-list tbody tr", text: /新しい人.*招待中/m

    # 招待中の人はログインできない（誰も知らないパスワードが入っている）
    delete ops_logout_path
    path = URI(url).path
    get path
    assert_select "#invitation dd", text: "new@example.com"

    patch path, params: { password: "", password_confirmation: "" }
    assert_response :unprocessable_entity
    patch path, params: { password: "newpassword1", password_confirmation: "different1" }
    assert_response :unprocessable_entity
    assert invited.reload.invited?

    patch path, params: { password: "newpassword1", password_confirmation: "newpassword1" }
    assert_redirected_to ops_root_path
    assert invited.reload.active?
    get ops_root_path
    assert_response :success

    # 使ったあとの URL は使えない
    delete ops_logout_path
    get path
    assert_response :not_found
    assert_select "#invitation-invalid"
    login("new@example.com", "newpassword1")
    assert_redirected_to ops_root_path
  end

  test "同じメールアドレスの運営者は加えられない" do
    login
    post ops_operators_path, params: { operator: { email: "operator@example.com", display_name: "重複" } }
    assert_response :unprocessable_entity
    assert_select "[role=alert]", text: /メールアドレス/
    assert_equal 1, Operator.count
  end

  test "招待の URL は3日で使えなくなり、再送すると前の URL は使えず新しい URL が使える" do
    login
    old_path = URI(invite).path
    invited = Operator.find_by!(email: "new@example.com")

    travel 3.days + 1.minute do
      get old_path
      assert_response :not_found

      get edit_ops_operator_path(invited)
      assert_select "#invitation", text: /有効期限が切れています/
      perform_enqueued_jobs { post resend_invitation_ops_operator_path(invited) }
      assert_redirected_to edit_ops_operator_path(invited)
      new_path = URI(ActionMailer::Base.deliveries.last.text_part.body.decoded[%r{https?://\S+/ops/invitations/\S+}]).path

      assert_not_equal old_path, new_path
      get old_path
      assert_response :not_found
      get new_path
      assert_response :success
    end
  end

  test "招待を取り消すと、行が消えて URL も使えない。有効な人は取り消せない" do
    login
    path = URI(invite).path
    invited = Operator.find_by!(email: "new@example.com")

    get edit_ops_operator_path(invited)
    assert_select "a#destroy-operator[href=?]", confirm_destroy_ops_operator_path(invited)
    get confirm_destroy_ops_operator_path(invited)
    assert_select "#destroy-confirmation", text: /new@example.com/
    delete ops_operator_path(invited)
    assert_redirected_to ops_operators_path
    assert_not Operator.exists?(invited.id)

    get path
    assert_response :not_found

    delete ops_operator_path(@operator)
    assert_response :not_found
  end

  test "ほかの運営者を停止すると入れなくなり、再開すると戻る。自分は停止できない" do
    other = Operator.create!(email: "other@example.com", password: PASSWORD, display_name: "ほかの人", status: :active)
    other_device = open_session
    other_device.post ops_login_path, params: { email: other.email, password: PASSWORD }
    login

    get edit_ops_operator_path(other)
    assert_select "a#suspend-operator[href=?]", confirm_suspend_ops_operator_path(other)
    get confirm_suspend_ops_operator_path(other)
    assert_select "#suspend-confirmation", text: /other@example.com/
    post suspend_ops_operator_path(other)
    assert_redirected_to edit_ops_operator_path(other)
    assert other.reload.suspended?
    other_device.get ops_root_path
    other_device.assert_redirected_to ops_login_path

    follow_redirect!
    assert_select "#suspension"
    post resume_ops_operator_path(other)
    assert other.reload.active?
    other_device.post ops_login_path, params: { email: other.email, password: PASSWORD }
    other_device.assert_redirected_to ops_root_path

    get edit_ops_operator_path(@operator)
    assert_select "#suspend-operator", 0
    get confirm_suspend_ops_operator_path(@operator)
    assert_response :not_found
    post suspend_ops_operator_path(@operator)
    assert_response :not_found
    assert @operator.reload.active?
  end

  test "表示名を変えられる。空にはできない" do
    login
    patch ops_operator_path(@operator), params: { operator: { display_name: "" } }
    assert_response :unprocessable_entity
    patch ops_operator_path(@operator), params: { operator: { display_name: "運用リーダー", email: "changed@example.com" } }
    assert_redirected_to ops_operators_path
    assert_equal "運用リーダー", @operator.reload.display_name
    assert_equal "operator@example.com", @operator.email
  end

  test "ログインしていなければ運営者の管理は開けない" do
    get ops_operators_path
    assert_redirected_to ops_login_path
  end
end
