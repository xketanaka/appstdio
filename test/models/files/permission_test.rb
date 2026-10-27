require "test_helper"

class Files::PermissionTest < ActiveSupport::TestCase
  setup do
    @tenant = Tenant.setup!(name: "テナントA")
    TenantContext.apply(tenant: @tenant)

    @alice = member("アリス")
    @bob = member("ボブ")
    @everyone = Group.everyone_of(@tenant)
    @sales = Group.create!(tenant: @tenant, name: "営業部")
    @sales1 = Group.create!(tenant: @tenant, parent: @sales, name: "営業1課")

    @drive = Files::Drive.create!(tenant: @tenant, kind: :shared)
    @root = folder("root", nil)
    @folder = folder("営業", @root)
    @child = folder("見積", @folder)
  end

  teardown do
    TenantContext.clear
  end

  describe ".nearest_on_path" do
    test "主体ごとに最も近い設定を、打ち消しも含めて返す" do
      grant(@root, @everyone, :viewer)
      grant(@root, @sales, :editor)
      grant(@folder, @sales, :viewer)
      grant(@folder, @everyone, :none)

      nearest = Files::Permission.nearest_on_path([@root.id, @folder.id])

      assert_equal "viewer", nearest[[@sales.id, nil]].role
      assert_equal "none", nearest[[@everyone.id, nil]].role
    end
  end

  describe ".manager_reachable?" do
    test "有効な人が管理者なら届いている" do
      grant(@root, @alice, :manager)

      assert Files::Permission.manager_reachable?(@child)
    end

    test "利用停止中の人だけが管理者なら届いていない" do
      grant(@root, @alice, :manager)
      @alice.update!(status: :suspended)

      assert_not Files::Permission.manager_reachable?(@child)
    end

    test "下位のグループのメンバーにも届く" do
      grant(@folder, @sales, :manager)
      GroupMember.create!(tenant: @tenant, group: @sales1, tenant_user: @alice)

      assert Files::Permission.manager_reachable?(@folder)
    end

    test "メンバーのいないグループだけが管理者なら届いていない" do
      grant(@folder, @sales, :manager)

      assert_not Files::Permission.manager_reachable?(@folder)
    end

    test "利用停止中のグループは数えない" do
      grant(@folder, @sales, :manager)
      GroupMember.create!(tenant: @tenant, group: @sales, tenant_user: @alice)
      @sales.suspend!(by: @bob)

      assert_not Files::Permission.manager_reachable?(@folder)
    end

    test "「全員」が管理者なら届いている" do
      grant(@root, @everyone, :manager)

      assert Files::Permission.manager_reachable?(@folder)
    end

    test "打ち消された管理者は数えない" do
      grant(@root, @alice, :manager)
      grant(@folder, @alice, :none)

      assert_not Files::Permission.manager_reachable?(@child)
    end
  end

  describe ".apply_changes!" do
    test "追加・変更・削除をまとめて反映し、履歴を残す" do
      grant(@folder, @alice, :manager)
      grant(@folder, @sales, :viewer)
      grant(@folder, @everyone, :none)

      Files::Permission.apply_changes!(@folder, [
        { group_id: @sales.id, tenant_user_id: nil, role: "editor" },
        { group_id: @everyone.id, tenant_user_id: nil, role: nil },
        { group_id: nil, tenant_user_id: @bob.id, role: "viewer" },
      ], actor: @alice)

      roles = @folder.permissions.to_h { [it.subject_key, it.role] }
      assert_equal({ [nil, @alice.id] => "manager", [@sales.id, nil] => "editor", [nil, @bob.id] => "viewer" }, roles)
      assert_equal "shared", Files::Activity.where(node: @folder).last.action
    end

    test "自分の管理者を外しても、他に管理者がいれば保存できる" do
      grant(@folder, @alice, :manager)
      grant(@folder, @bob, :manager)

      Files::Permission.apply_changes!(@folder, [{ group_id: nil, tenant_user_id: @alice.id, role: "viewer" }], actor: @alice)

      assert @folder.permissions.find_by(tenant_user: @alice).role_viewer?
    end

    test "管理者が1人もいなくなる変更は、何も残さずに断る" do
      grant(@root, @alice, :manager)

      assert_raises(Files::Permission::NoManagerError) do
        Files::Permission.apply_changes!(@folder, [
          { group_id: nil, tenant_user_id: @alice.id, role: "none" },
          { group_id: nil, tenant_user_id: @bob.id, role: "viewer" },
        ], actor: @alice)
      end

      assert_empty @folder.permissions
      assert_not Files::Activity.exists?(node: @folder, action: :shared)
    end

    test "もとから管理者のいないノードは断らない" do
      Files::Permission.apply_changes!(@folder, [{ group_id: @everyone.id, tenant_user_id: nil, role: "viewer" }], actor: @alice)

      assert @folder.permissions.find_by(group: @everyone).role_viewer?
    end
  end

  private

  def member(name)
    user = User.create!(email: "#{SecureRandom.hex(4)}@example.com", password: "password1234")
    TenantUser.create!(tenant: @tenant, user: user, display_name: name, role: :member, status: :active)
  end

  def folder(name, parent)
    Files::Node.create!(tenant: @tenant, drive: @drive, parent: parent, kind: :folder, name: name)
  end

  def grant(node, subject, role)
    subject_key = subject.is_a?(Group) ? :group : :tenant_user
    Files::Permission.create!(tenant: @tenant, node: node, subject_key => subject, role: role)
  end
end
