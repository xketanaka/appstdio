require "test_helper"

class Files::NodeTest < ActiveSupport::TestCase
  setup do
    @tenant = Tenant.setup!(name: "テナントA")
    user = User.create!(email: "a@example.com", password: "password1234")
    TenantContext.apply(tenant: @tenant)
    @member = TenantUser.create!(tenant: @tenant, user: user, display_name: "Aさん", status: :active)
    @root = Files::Drive.shared_root(@tenant)
  end

  teardown do
    TenantContext.clear
  end

  describe ".create_folder!" do
    test "作った人を管理者にし、操作履歴を残す" do
      folder = Files::Node.create_folder!(parent: @root, name: " 営業 ", creator: @member)

      assert_equal "営業", folder.name, "前後の空白は取り除く"
      assert_predicate folder, :folder?
      assert_equal @root.drive_id, folder.drive_id
      assert_equal [[@member.id, "manager"]], folder.permissions.pluck(:tenant_user_id, :role)
      assert_equal [[@member.id, "created"]], Files::Activity.where(node: folder).pluck(:actor_id, :action)
      assert_equal "manager", Files::Access.new(@member).effective_permission(folder).role
    end

    test "同じフォルダに同じ名前があれば作らない" do
      Files::Node.create_folder!(parent: @root, name: "営業", creator: @member)

      error = assert_raises(ActiveRecord::RecordInvalid) do
        Files::Node.create_folder!(parent: @root, name: "営業", creator: @member)
      end
      assert_equal ["名前が同じフォルダの中のものと重複しています。"], error.record.errors.full_messages
      assert_equal 1, Files::Node.where(name: "営業").count
      assert_equal 1, Files::Activity.count, "失敗したときは権限も操作履歴も残さない"
    end

    test "ゴミ箱の中のものとは重複してよく、大文字と小文字は区別する" do
      trashed = Files::Node.create_folder!(parent: @root, name: "Report", creator: @member)
      trashed.update!(deleted_at: Time.current, deleted_root_id: trashed.id)

      assert_nothing_raised do
        Files::Node.create_folder!(parent: @root, name: "Report", creator: @member)
        Files::Node.create_folder!(parent: @root, name: "report", creator: @member)
      end
    end
  end

  describe ".move!" do
    setup do
      @sales = Files::Node.create_folder!(parent: @root, name: "営業", creator: @member)
      @general = Files::Node.create_folder!(parent: @root, name: "総務", creator: @member)
      @estimate = Files::Node.create!(tenant: @tenant, drive_id: @root.drive_id, parent: @sales, kind: :file, name: "見積.xlsx")
    end

    test "移して、移した人と移動元・移動先を操作履歴に残す" do
      Files::Node.move!([@estimate, @sales], to: @general, actor: @member)

      assert_equal @general.id, @estimate.reload.parent_id
      assert_equal @general.id, @sales.reload.parent_id
      assert_equal(
        [@estimate.id, @member.id, { "from" => @sales.id, "to" => @general.id }],
        Files::Activity.moved.order(:id).pick(:node_id, :actor_id, :detail),
      )
    end

    test "ドライブをまたいで移せる" do
      personal_root = Files::Drive.personal_root(@member)

      Files::Node.move!([@sales], to: personal_root, actor: @member)

      assert_equal personal_root.drive_id, @estimate.reload.drive_id
    end

    test "移動先に同じ名前があれば、1件も移さない" do
      Files::Node.create!(tenant: @tenant, drive_id: @root.drive_id, parent: @general, kind: :file, name: "見積.xlsx")
      other = Files::Node.create!(tenant: @tenant, drive_id: @root.drive_id, parent: @sales, kind: :file, name: "価格表.xlsx")

      error = assert_raises(Files::Node::MoveError) do
        Files::Node.move!([other, @estimate], to: @general, actor: @member)
      end
      assert_equal ["移動先に「見積.xlsx」と同じ名前のものがあります。"], error.messages
      assert_equal @sales.id, other.reload.parent_id
      assert_empty Files::Activity.moved
    end

    test "それ自身や配下へは移せない" do
      error = assert_raises(Files::Node::MoveError) do
        Files::Node.move!([@root.children.find_by!(name: "営業")], to: @sales, actor: @member)
      end
      assert_equal ["「営業」は、それ自身やその中のフォルダへは移動できません。"], error.messages
    end

    test "今と同じ場所への移動は何もしない" do
      Files::Node.move!([@estimate], to: @sales, actor: @member)

      assert_empty Files::Activity.moved
    end
  end
end
