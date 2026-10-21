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
end
