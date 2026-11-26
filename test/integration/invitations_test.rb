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
    url = mail.text_part.body.decoded[%r{https?://\S+/invitations/\S+}]
    URI(url).path if url
  end

  def tenant_user_of(email)
    TenantContext.switch(tenant: @tenant) { TenantUser.joins(:user).find_by!(users: { email: }) }
  end

  test "追加すると招待メールを送り、新しいアカウントはパスワードを決めて参加し、そのテナントに入る" do
    path = invite("new@example.com")

    mail = ActionMailer::Base.deliveries.last
    assert_equal ["new@example.com"], mail.to
    assert_equal "AppStdio(テナントA) に招待されました", mail.subject
    assert_includes mail.text_part.body.decoded, "管理者さんさんから、AppStdio(テナントA) に招待されました。"
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

  test "パスワードのあるアカウントは、メールの URL を開かずに、ログインして組織の選択から参加する" do
    TenantContext.switch(tenant: @other_tenant) do
      TenantUser.create!(tenant: @other_tenant, user: User.create!(email: "b@example.com", password: PASSWORD,
        last_signed_in_at: 1.day.ago), display_name: "Bさん", role: :owner, status: :active)
    end
    # 組織設定のタイトルラベルがあれば、システム名として添える
    TenantContext.switch(tenant: @tenant) { @tenant.setting.update!(title_label: "経費精算システム") }
    assert_nil invite("b@example.com", display_name: "Bさん")
    mail = ActionMailer::Base.deliveries.last
    assert_equal "AppStdio: 経費精算システム(テナントA) に招待されました", mail.subject
    body = mail.text_part.body.decoded
    assert_includes body, "組織の選択で「テナントA」を選ぶと参加できます"
    assert_includes body, "http://example.com/login"

    post login_path, params: { email: "b@example.com", password: PASSWORD }
    follow_redirect!
    assert_select "#tenant-list li", 2
    assert_select "#tenant-list li", text: /テナントA\s*招待されています/
    assert tenant_user_of("b@example.com").invited?

    post select_tenant_path, params: { tenant_id: @tenant.id }
    assert_redirected_to top_page_path
    assert tenant_user_of("b@example.com").active?
    follow_redirect!
    assert_select "[role=status]", text: "「テナントA」に参加しました。"
    assert_select "#site-header", text: /テナントA/
  end

  test "所属が招待中の1つだけなら、自動では入らずに選ぶのを待つ" do
    path = invite("new@example.com")
    # 招待の URL の期限が切れても、パスワードを決めればログインして参加できる
    travel 4.days
    get path
    assert_response :not_found
    User.find_by!(email: "new@example.com").update!(password: "newpassword1", last_signed_in_at: Time.current)

    post login_path, params: { email: "new@example.com", password: "newpassword1" }
    follow_redirect!
    assert_response :success
    assert_select "#tenant-list li", 1
    assert tenant_user_of("new@example.com").invited?

    post select_tenant_path, params: { tenant_id: @tenant.id }
    assert tenant_user_of("new@example.com").active?
  end

  test "パスワードを決めたあとに開いた URL と、別の人でログインして開いた URL では参加させない" do
    path = invite("new@example.com")

    login("admin@example.com")
    get path
    assert_select "#other-account", text: /admin@example.com/
    patch path, params: { password: "newpassword1", password_confirmation: "newpassword1" }
    assert_redirected_to path
    assert tenant_user_of("new@example.com").invited?
    delete logout_path

    User.find_by!(email: "new@example.com").update!(password: "newpassword1", last_signed_in_at: Time.current)
    get path
    assert_select "#existing-account", text: /組織の選択で「テナントA」を選ぶと参加できます/
    assert_select "#invitation input[type=password]", 0
    patch path, params: { password: "other-password", password_confirmation: "other-password" }
    assert_redirected_to path
    assert tenant_user_of("new@example.com").invited?
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
