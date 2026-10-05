require "test_helper"

class Files::DriveTest < ActiveSupport::TestCase
  setup do
    @tenant = Tenant.create!(name: "テナントA")
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
      assert_equal "viewer", Files::Access.new(@member).role(root)
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
      assert_equal "manager", Files::Access.new(@member).role(root)
    end

    test "他の利用者には見えない" do
      other_user = User.create!(email: "b@example.com", password: "password1234")
      other = TenantUser.create!(tenant: @tenant, user: other_user, display_name: "Bさん", status: :active)

      root = Files::Drive.personal_root(@member)

      assert_nil Files::Access.new(other).role(root)
      assert_not_equal root, Files::Drive.personal_root(other)
    end
  end
end
