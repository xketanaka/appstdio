require "test_helper"

class Files::DriveTest < ActiveSupport::TestCase
  setup do
    @tenant = Tenant.setup!(name: "テナントA")
    TenantContext.apply(tenant: @tenant)
    user = User.create!(email: "a@example.com", password: "password1234")
    @member = TenantUser.create!(tenant: @tenant, user: user, display_name: "Aさん", status: :active)
  end

  teardown do
    TenantContext.clear
  end

  describe ".shared_root" do
    test "初めて開いたときに「全員=閲覧者」を付けて作る" do
      root = Files::Drive.shared_root(@tenant)

      assert root.root?
      assert root.drive.shared?
      assert_equal [["全員", "viewer"]], root.permissions.map { |p| [p.group.name, p.role] }
      assert_equal "viewer", Files::Access.new(@member).effective_permission(root).role
    end

    test "2回目以降は同じルートを返す" do
      assert_equal Files::Drive.shared_root(@tenant), Files::Drive.shared_root(@tenant)
      assert_equal 1, Files::Drive.count
    end
  end

  describe ".personal_root" do
    test "初めて開いたときに本人を管理者にして作る" do
      root = Files::Drive.personal_root(@member)

      assert root.drive.personal?
      assert_equal @member, root.drive.owner
      assert_equal "manager", Files::Access.new(@member).effective_permission(root).role
    end

    test "他の利用者には見えない" do
      other_user = User.create!(email: "b@example.com", password: "password1234")
      other = TenantUser.create!(tenant: @tenant, user: other_user, display_name: "Bさん", status: :active)

      root = Files::Drive.personal_root(@member)

      assert_nil Files::Access.new(other).effective_permission(root).role
      assert_not_equal root, Files::Drive.personal_root(other)
    end
  end

  describe "グループドライブ" do
    setup do
      @sales = Group.create!(tenant: @tenant, name: "営業部")
      @sales1 = Group.create!(tenant: @tenant, parent: @sales, name: "営業1課")
      @leader = member("営業部の管理者")
      @sub_member = member("営業1課の人")
      @admin = member("テナント管理者", role: :admin)
      GroupMember.create!(tenant: @tenant, group: @sales, tenant_user: @leader, role: :leader)
      GroupMember.create!(tenant: @tenant, group: @sales1, tenant_user: @sub_member)
    end

    test "グループ=編集者を付けて作り、下位グループのメンバーにも届く。グループ管理者は管理者になる" do
      root = Files::Drive.group_root(@sales)

      assert root.drive.group_drive?
      assert_equal [["営業部", "editor"]], root.permissions.map { |p| [p.group.name, p.role] }
      assert_equal "editor", Files::Access.new(@sub_member).effective_permission(root).role
      assert_equal "manager", Files::Access.new(@leader).effective_permission(root).role
      assert_nil Files::Access.new(@member).effective_permission(root).role
    end

    test "グループ管理者の印を外すと、管理者でなくなる（権限の行を付け直さなくてよい）" do
      root = Files::Drive.group_root(@sales)

      @sales.replace_members({ @leader.id => "member" })

      assert_equal "editor", Files::Access.new(@leader).effective_permission(root).role
    end

    test "使わないにすると、中身は特権モードでも見えず、もう一度使うと元どおり見える" do
      root = Files::Drive.group_root(@sales)
      folder = Files::Node.create_folder!(parent: root, name: "見積", creator: @sub_member)

      root.drive.disable!(actor: @leader, trash: false)

      assert_not Files::Access.new(@sub_member).effective_permission(folder).readable?
      assert_not Files::Access.new(@admin, privileged: true).effective_permission(folder).readable?
      assert_empty Files::Access.new(@admin, privileged: true).readable(Files::Node.where(id: folder.id))

      Files::Drive.enable_for!(@sales)

      assert Files::Access.new(@sub_member).effective_permission(folder).readable?
      assert folder.reload.deleted_at.nil?
    end

    test "使わないにするとき、中身をゴミ箱へ入れられる。使わない間はゴミ箱にも出ない" do
      root = Files::Drive.group_root(@sales)
      folder = Files::Node.create_folder!(parent: root, name: "見積", creator: @sub_member)

      root.drive.disable!(actor: @leader, trash: true)

      assert folder.reload.deleted_at
      assert_empty Files::Access.new(@sub_member).trash

      Files::Drive.enable_for!(@sales)

      assert_equal [folder], Files::Access.new(@sub_member).trash
    end

    test "グループを利用停止にすると、グループ管理者にも見えなくなる" do
      root = Files::Drive.group_root(@sales)

      @sales.suspend!(by: @admin)

      assert_not Files::Access.new(@leader).effective_permission(root).readable?
    end

    test "グループを消すと、下位のグループのドライブも中身を完全削除し、使用量から引く" do
      sales_root = Files::Drive.group_root(@sales)
      sales1_root = Files::Drive.group_root(@sales1)
      blob = ActiveStorage::Blob.create_and_upload!(io: StringIO.new("abc"), filename: "見積書.txt")
      file = Files::Node.create_file!(parent: sales1_root, blob:, creator: @sub_member)
      folder = Files::Node.create_folder!(parent: sales_root, name: "見積", creator: @sub_member)

      @sales.destroy_with_cascades!

      assert_equal 0, @tenant.files_setting.reload.storage_used_bytes
      assert [file, folder, sales_root, sales1_root].all? { it.reload.purged_at }
      assert_nil sales_root.drive.reload.group_id
      assert_nil file.current_version.reload.body.attachment
    end
  end

  private

  def member(name, role: :member)
    user = User.create!(email: "#{SecureRandom.hex(4)}@example.com", password: "password1234")
    TenantUser.create!(tenant: @tenant, user:, display_name: name, role:, status: :active)
  end
end
