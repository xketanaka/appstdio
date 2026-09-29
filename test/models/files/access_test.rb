require "test_helper"

class Files::AccessTest < ActiveSupport::TestCase
  setup do
    @tenant = Tenant.create!(name: "テナントA")
    TenantContext.apply(tenant: @tenant)

    @sales1_member = member("営業1課の人")
    @general_member = member("総務の人")
    @outsider = member("どこにも属さない人")
    @admin = member("テナント管理者", role: :admin)

    @everyone = Group.create!(tenant: @tenant, kind: :everyone, name: "全員")
    @sales = Group.create!(tenant: @tenant, name: "営業部")
    @sales1 = Group.create!(tenant: @tenant, parent: @sales, name: "営業1課")
    @general = Group.create!(tenant: @tenant, name: "総務部")
    GroupMember.create!(tenant: @tenant, group: @sales1, tenant_user: @sales1_member)
    GroupMember.create!(tenant: @tenant, group: @general, tenant_user: @general_member)

    @drive = Files::Drive.create!(tenant: @tenant, kind: :shared)
    @root = folder("root", nil)
    @sales_folder = folder("営業", @root)
    @estimates = folder("見積", @sales_folder)
    @estimate = file("見積書.xlsx", @estimates)
    grant(@root, @everyone, :viewer)
    grant(@sales_folder, @sales, :editor)
  end

  teardown do
    TenantContext.clear
  end

  test "ルートの「全員=閲覧者」が配下すべてに継承される" do
    assert_equal "viewer", access(@outsider).role(@estimate)
  end

  test "上位グループへの付与は下位グループのメンバーに届く" do
    assert_equal "editor", access(@sales1_member).role(@estimates)
  end

  test "未設定は主体ごとに判定する" do
    grant(@estimates, @general, :viewer)

    assert_equal "editor", access(@sales1_member).role(@estimates)
    assert_equal "viewer", access(@general_member).role(@estimates)
  end

  test "同じ主体への設定は最も近いものが効き、子で下げられる" do
    grant(@estimates, @sales, :viewer)

    assert_equal "editor", access(@sales1_member).role(@sales_folder)
    assert_equal "viewer", access(@sales1_member).role(@estimates)
    assert_equal "viewer", access(@sales1_member).role(@estimate)
  end

  test "打ち消しはその主体の継承だけを無効にし、子孫にも効く" do
    grant(@estimates, @sales, :none)

    assert_equal "viewer", access(@sales1_member).role(@estimate), "全員からの閲覧者は残る"

    grant(@estimates, @everyone, :none)
    assert_nil access(@sales1_member).role(@estimates)
    assert_nil access(@sales1_member).role(@estimate)
  end

  test "打ち消した主体に孫で付与し直せる" do
    grant(@sales_folder, @everyone, :none)
    grant(@estimates, @everyone, :viewer)

    assert_nil access(@outsider).role(@sales_folder)
    assert_equal "viewer", access(@outsider).role(@estimate)
  end

  test "下位グループの打ち消しでは上位グループへの付与を除外できない" do
    grant(@estimates, @sales1, :none)

    assert_equal "editor", access(@sales1_member).role(@estimates)
  end

  test "本人への付与とグループへの付与は強い方を採る" do
    grant(@estimates, @sales1_member, :manager)
    grant(@sales_folder, @outsider, :none)

    assert_equal "manager", access(@sales1_member).role(@estimate)
    assert_equal "viewer", access(@outsider).role(@estimate), "本人の打ち消しでは全員は消えない"
  end

  test "移動すると移動先の権限を継承する" do
    general_folder = folder("総務", @root)
    grant(general_folder, @general, :editor)

    @estimates.update!(parent: general_folder)

    assert_equal "viewer", access(@sales1_member).role(@estimate)
    assert_equal "editor", access(@general_member).role(@estimate)
  end

  test "テナント管理者はすべてのノードで管理者になる" do
    grant(@sales_folder, @everyone, :none)

    assert_equal "manager", access(@admin).role(@estimate)
    assert_equal Files::Node.count, access(@admin).readable(Files::Node.all).count
  end

  test "権限の無いノードは結果に含まれない" do
    hr = folder("人事", @root)
    grant(hr, @everyone, :none)

    roles = access(@outsider).roles([@sales_folder, hr])

    assert_equal({ @sales_folder.id => "viewer" }, roles)
  end

  test "readable は閲覧できるノードだけに絞る" do
    hr = folder("人事", @root)
    review = file("評価.xlsx", hr)
    grant(hr, @everyone, :none)

    readable = access(@outsider).readable(Files::Node.all)

    assert_includes readable, @estimate
    assert_not_includes readable, hr
    assert_not_includes readable, review
  end

  test "親が見えず自分が見えるノードが共有されたアイテムになる" do
    hr = folder("人事", @root)
    review = file("評価.xlsx", hr)
    grant(hr, @everyone, :none)
    grant(review, @outsider, :viewer)
    grant(@estimate, @outsider, :editor)

    assert_equal [review], access(@outsider).shared_items
  end

  test "テナント管理者の共有されたアイテムは付与された権限だけで判定する" do
    hr = folder("人事", @root)
    review = file("評価.xlsx", hr)
    grant(hr, @everyone, :none)
    grant(review, @admin, :viewer)

    assert_equal [review], access(@admin).shared_items
  end

  test "ゴミ箱には削除されたノードの親の編集者にだけ出る" do
    @estimate.update!(deleted_at: Time.current, deleted_root_id: @estimate.id)

    assert_equal [@estimate], access(@sales1_member).trash
    assert_empty access(@outsider).trash
    assert_equal [@estimate], access(@admin).trash
  end

  test "権限の強さを比べられる" do
    assert Files::Access.at_least?("manager", :editor)
    assert Files::Access.at_least?("editor", :editor)
    assert_not Files::Access.at_least?("viewer", :editor)
    assert_not Files::Access.at_least?(nil, :viewer)
  end

  private

  def member(name, role: :member)
    user = User.create!(email: "#{SecureRandom.hex(4)}@example.com", password: "password1234")
    TenantUser.create!(tenant: @tenant, user: user, display_name: name, role: role, status: :active)
  end

  def folder(name, parent)
    Files::Node.create!(tenant: @tenant, drive: @drive, parent: parent, kind: :folder, name: name)
  end

  def file(name, parent)
    Files::Node.create!(tenant: @tenant, drive: @drive, parent: parent, kind: :file, name: name)
  end

  def grant(node, subject, role)
    subject_key = subject.is_a?(Group) ? :group : :tenant_user
    Files::Permission.create!(tenant: @tenant, node: node, subject_key => subject, role: role)
  end

  def access(tenant_user)
    Files::Access.new(tenant_user)
  end
end
