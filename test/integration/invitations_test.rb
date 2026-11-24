require "test_helper"

class InvitationsTest < ActionDispatch::IntegrationTest
  PASSWORD = "password1234".freeze

  setup do
    @tenant = Tenant.setup!(name: "テナントA")
    @other_tenant = Tenant.setup!(name: "テナントB")
    TenantContext.switch(tenant: @tenant) do
      @admin = TenantUser.create!(tenant: @tenant, user: User.create!(email: "admin@example.com", password: PASSWORD),
        display_name: "管理者さん", role: :admin, status: :active)
    end
    ActionMailer::Base.deliveries.clear
  end

  teardown do
    TenantContext.clear
  end

  # テナントが1つならテナントの選択を経て入る
  def login(email, password = PASSWORD)
    post login_path, params: { email:, password: }
    follow_redirect!
    follow_redirect!
  end

  # 利用者を追加して招待メールを送り、メールの URL のパスを返す
  def invite(email, display_name: "新人さん")
    login("admin@example.com")
    perform_enqueued_jobs do
      post management_users_path, params: { tenant_user: { email:, display_name:, role: "member", label_names: "" } }
    end
    delete logout_path
    url_in(ActionMailer::Base.deliveries.last)
  end

  def url_in(mail)
    URI(mail.text_part.body.decoded[%r{https?://\S+/invitations/\S+}]).path
  end

  def tenant_user_of(email)
    TenantContext.switch(tenant: @tenant) { TenantUser.joins(:user).find_by!(users: { email: }) }
  end

  test "追加すると招待メールを送り、新しいアカウントはパスワードを決めて参加し、そのテナントに入る" do
    path = invite("new@example.com")

    mail = ActionMailer::Base.deliveries.last
    assert_equal ["new@example.com"], mail.to
    assert_equal "「テナントA」に招待されました", mail.subject
    assert_includes mail.text_part.body.decoded, "管理者さんさんから"
    assert tenant_user_of("new@example.com").invited?

    get path
    assert_select "#invitation h1", text: "「テナントA」への招待"
    assert_select "#invitation input[name=password_confirmation]"

    # 確認が合わない・空なら参加しない
    patch path, params: { password: "newpassword1", password_confirmation: "different1" }
    assert_response :unprocessable_entity
    assert_select "[role=alert]", text: /パスワード（確認）/
    patch path, params: { password: "", password_confirmation: "" }
    assert_response :unprocessable_entity
    assert tenant_user_of("new@example.com").invited?

    patch path, params: { password: "newpassword1", password_confirmation: "newpassword1" }
    assert_redirected_to top_page_path
    follow_redirect!
    assert_select "[role=status]", text: "「テナントA」に参加しました。"
    tenant_user = tenant_user_of("new@example.com")
    assert tenant_user.active?
    assert tenant_user.user.email_verified?
    assert tenant_user.user.authenticate("newpassword1")

    # 参加したあとは同じ URL は使えない
    delete logout_path
    get path
    assert_response :not_found
    assert_select "#invitation-invalid"
  end

  test "他のテナントで使っているアカウントは、ログインしていなければ今のパスワードで参加する" do
    TenantContext.switch(tenant: @other_tenant) do
      TenantUser.create!(tenant: @other_tenant, user: User.create!(email: "b@example.com", password: PASSWORD,
        last_signed_in_at: 1.day.ago), display_name: "Bさん", role: :owner, status: :active)
    end
    path = invite("b@example.com", display_name: "Bさん")

    get path
    assert_select "#invitation input[name=password_confirmation]", 0
    assert_select "#forgot-password[href=?]", new_password_reset_path
    patch path, params: { password: "wrong-password" }
    assert_response :unprocessable_entity
    assert_select "[role=alert]", text: "パスワードが正しくありません。"
    assert tenant_user_of("b@example.com").invited?

    patch path, params: { password: PASSWORD }
    assert_redirected_to top_page_path
    assert tenant_user_of("b@example.com").active?
  end

  test "招待された本人でログインしていれば「参加する」だけで参加し、別の人なら参加させない" do
    TenantContext.switch(tenant: @other_tenant) do
      TenantUser.create!(tenant: @other_tenant, user: User.create!(email: "b@example.com", password: PASSWORD),
        display_name: "Bさん", role: :owner, status: :active)
    end
    path = invite("b@example.com", display_name: "Bさん")

    login("admin@example.com")
    get path
    assert_select "#other-account", text: /admin@example.com/
    patch path
    assert_response :unprocessable_entity
    assert tenant_user_of("b@example.com").invited?
    delete logout_path

    login("b@example.com")
    get path
    assert_select "#invitation input[type=password]", 0
    patch path
    assert_redirected_to top_page_path
    assert tenant_user_of("b@example.com").active?
    follow_redirect!
    assert_select "#site-header", text: /テナントA/
  end

  test "期限は組織設定の日数で、過ぎると使えない" do
    path = invite("new@example.com")

    travel 3.days - 1.minute do
      get path
      assert_response :success
    end
    travel 3.days + 1.minute do
      get path
      assert_response :not_found
      TenantContext.switch(tenant: @tenant) { TenantSetting.find_by!(tenant: @tenant).update!(invitation_expiry_days: 7) }
      get path
      assert_response :success
    end
  end

  test "再送すると前の URL は使えず、新しい URL で参加できる" do
    old_path = invite("new@example.com")
    tenant_user = tenant_user_of("new@example.com")

    login("admin@example.com")
    get management_user_path(tenant_user)
    assert_select "#invitation", text: /有効期限は/
    travel 1.second do
      perform_enqueued_jobs { post resend_invitation_management_user_path(tenant_user) }
    end
    assert_redirected_to management_user_path(tenant_user)
    new_path = url_in(ActionMailer::Base.deliveries.last)
    delete logout_path

    assert_not_equal old_path, new_path
    get old_path
    assert_response :not_found
    get new_path
    assert_response :success
  end

  test "改ざんした URL は使えない" do
    path = invite("new@example.com")

    get path.sub(/.\z/) { it == "A" ? "B" : "A" }
    assert_response :not_found
    get "/invitations/foo"
    assert_response :not_found
  end

  test "有効な人には再送できず、メンバーは再送できない" do
    login("admin@example.com")
    post resend_invitation_management_user_path(@admin)
    assert_response :not_found

    invite("new@example.com")
    tenant_user = tenant_user_of("new@example.com")
    TenantContext.switch(tenant: @tenant) do
      TenantUser.create!(tenant: @tenant, user: User.create!(email: "member@example.com", password: PASSWORD),
        display_name: "メンバーさん", role: :member, status: :active)
    end
    login("member@example.com")
    post resend_invitation_management_user_path(tenant_user)
    assert_response :not_found
  end
end
