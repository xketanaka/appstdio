require "application_system_test_case"

class FilesSystemTest < ApplicationSystemTestCase
  PASSWORD = "password1234".freeze

  setup do
    @tenant = Tenant.setup!(name: "テナントA")
    @owner_user = User.create!(email: "owner@example.com", password: PASSWORD)

    TenantContext.switch(tenant: @tenant) do
      @owner = TenantUser.create!(
        tenant: @tenant, user: @owner_user, display_name: "管理者さん", role: :owner, status: :active,
      )
      root = Files::Drive.shared_root(@tenant)
      @sales = node(:folder, "営業", root)
      node(:folder, "見積", @sales)
      hr = node(:folder, "人事", root)
      Files::Permission.create!(tenant: @tenant, node: hr, group: Group.everyone_of(@tenant), role: :none)
      Files::Drive.personal_root(@owner)
    end
    TenantContext.clear

    visit login_path
    fill_in "email", with: @owner_user.email
    fill_in "password", with: PASSWORD
    click_on "ログイン"
    assert_text "ログインしています"
  end

  test "フォルダを移ってもページを読み直さず、左ペインで開いた区分は閉じない" do
    visit files_root_path
    assert_selector "h1", text: "組織共有ドライブ"
    execute_script("window.notReloaded = true")

    within("#side-pane") { find("summary", text: "マイドライブ").find("svg").click }
    within("#file-list") { click_on "営業" }

    assert_selector "h1", text: "営業"
    assert_current_path files_folder_path(@sales)
    assert evaluate_script("window.notReloaded")
    assert_selector "#side-pane details[open]", count: 2

    go_back
    assert_selector "h1", text: "組織共有ドライブ"
  end

  test "URL を直接開いても同じ画面になる" do
    visit files_folder_path(@sales)

    assert_selector "h1", text: "営業"
    assert_selector "nav[aria-label='現在の場所'] a", text: "組織共有ドライブ"
    assert_title "AppStdio - 営業"
  end

  test "特権モードにすると権限の無いフォルダも開け、終えるとドライブのルートに戻る" do
    visit files_root_path
    assert_no_selector "#file-list a", text: "人事"

    within("#side-pane") { find("button[role=switch]").click }
    assert_selector "[role=status]", text: "特権モードです"
    within("#file-list") { click_on "人事" }
    assert_selector "h1", text: "人事"

    within("[role=status]") { click_on "特権モードを終える" }
    assert_no_selector "[role=status]"
    assert_current_path files_root_path
    assert_no_selector "#file-list a", text: "人事"
  end

  private

  def node(kind, name, parent)
    Files::Node.create!(tenant: @tenant, drive: parent.drive, parent: parent, kind: kind, name: name, creator: @owner)
  end
end
