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

      error = assert_raises(Files::Node::OperationError) do
        Files::Node.move!([other, @estimate], to: @general, actor: @member)
      end
      assert_equal ["移動先に「見積.xlsx」と同じ名前のものがあります。"], error.messages
      assert_equal @sales.id, other.reload.parent_id
      assert_empty Files::Activity.moved
    end

    test "それ自身や配下へは移せない" do
      error = assert_raises(Files::Node::OperationError) do
        Files::Node.move!([@root.children.find_by!(name: "営業")], to: @sales, actor: @member)
      end
      assert_equal ["「営業」は、それ自身やその中のフォルダへは移動できません。"], error.messages
    end

    test "今と同じ場所への移動は何もしない" do
      Files::Node.move!([@estimate], to: @sales, actor: @member)

      assert_empty Files::Activity.moved
    end
  end

  describe ".create_file!" do
    setup do
      @blob = ActiveStorage::Blob.create_and_upload!(io: StringIO.new("見積の中身"), filename: "見積.txt")
    end

    test "版1を作って中身を付け、容量を数え、作った人を管理者にして操作履歴を残す" do
      file = Files::Node.create_file!(parent: @root, blob: @blob, creator: @member)

      assert_predicate file, :file?
      assert_equal ["見積.txt", @blob.byte_size], [file.name, file.byte_size]
      assert_equal [1, @blob.id], [file.current_version.number, file.current_version.body.blob.id]
      assert_equal @blob.byte_size, @tenant.files_setting.reload.storage_used_bytes
      assert_equal "manager", Files::Access.new(@member).effective_permission(file).role
      assert_equal ["created"], Files::Activity.where(node: file).pluck(:action)
    end

    test "容量が足りなければ何も残さない" do
      @tenant.files_setting.update!(storage_limit_bytes: @blob.byte_size - 1)

      assert_raises(Files::Node::StorageFullError) do
        Files::Node.create_file!(parent: @root, blob: @blob, creator: @member)
      end
      assert_equal 0, @tenant.files_setting.reload.storage_used_bytes
      assert_not Files::Node.exists?(name: "見積.txt")
    end

    test "同じ名前があれば作らず、数えた容量も戻す" do
      Files::Node.create_folder!(parent: @root, name: "見積.txt", creator: @member)

      assert_raises(ActiveRecord::RecordInvalid) do
        Files::Node.create_file!(parent: @root, blob: @blob, creator: @member)
      end
      assert_equal 0, @tenant.files_setting.reload.storage_used_bytes
    end
  end

  describe "名前の変更・ゴミ箱・復元" do
    setup do
      @sales = Files::Node.create_folder!(parent: @root, name: "営業", creator: @member)
      @estimates = Files::Node.create_folder!(parent: @sales, name: "見積", creator: @member)
      @memo = Files::Node.create!(tenant: @tenant, drive_id: @root.drive_id, parent: @estimates, kind: :file, name: "メモ.txt")
    end

    test "名前を変えると、変更前と変更後を操作履歴に残す。同じ名前なら残さない" do
      @memo.rename!(" メモ.md ", actor: @member)
      @memo.rename!("メモ.md", actor: @member)

      assert_equal "メモ.md", @memo.reload.name
      assert_equal [{ "from" => "メモ.txt", "to" => "メモ.md" }], Files::Activity.renamed.pluck(:detail)
    end

    test "フォルダをゴミ箱へ入れると、配下もまとめて入り、復元でまとめて戻る" do
      Files::Node.trash!([@sales, @memo], actor: @member)

      assert_equal [@sales.id] * 3, [@sales, @estimates, @memo].map { it.reload.deleted_root_id }
      assert_equal [@sales], Files::Node.trash_roots.to_a
      assert_equal ["deleted"], Files::Activity.deleted.pluck(:action)

      Files::Node.restore!([@sales], actor: @member)
      assert_equal [nil] * 3, [@sales, @estimates, @memo].map { it.reload.deleted_at }
      assert_equal 1, Files::Activity.restored.count
    end

    test "元のフォルダもゴミ箱にあれば、戻さずに理由を返す" do
      Files::Node.trash!([@memo], actor: @member)
      Files::Node.trash!([@estimates], actor: @member)

      error = assert_raises(Files::Node::OperationError) { Files::Node.restore!([@memo.reload], actor: @member) }
      assert_equal ["「メモ.txt」の元のフォルダ「見積」がゴミ箱にあります。先にそのフォルダを元に戻してください。"], error.messages
      assert_not_nil @memo.reload.deleted_at
    end

    test "元の場所に同じ名前のものができていれば、戻さない" do
      Files::Node.trash!([@memo], actor: @member)
      Files::Node.create!(tenant: @tenant, drive_id: @root.drive_id, parent: @estimates, kind: :file, name: "メモ.txt")

      error = assert_raises(Files::Node::OperationError) { Files::Node.restore!([@memo.reload], actor: @member) }
      assert_equal ["元の場所に「メモ.txt」と同じ名前のものがあります。"], error.messages
    end
  end
end
