require "test_helper"

# バリデーションを迂回するため insert_all や update_column で書き込んでいる
class Files::SchemaTest < ActiveSupport::TestCase
  setup do
    @tenant = Tenant.create!(name: "テナントA")
    @user = User.create!(email: "a@example.com", password: "password1234")
    @member = TenantContext.switch(tenant: @tenant) do
      TenantUser.create!(tenant: @tenant, user: @user, display_name: "Aさん", status: :active)
    end
    TenantContext.apply(tenant: @tenant, user: @user)
    @drive = Files::Drive.create!(tenant: @tenant, kind: :shared)
    @root = Files::Node.create!(tenant: @tenant, drive: @drive, kind: :folder, name: "root")
  end

  teardown do
    TenantContext.clear
  end

  test "ドライブのルートは1つだけ" do
    assert_raises(ActiveRecord::RecordNotUnique) do
      Files::Node.create!(tenant: @tenant, drive: @drive, kind: :folder, name: "root2")
    end
  end

  test "同一フォルダ内の同名は作れない" do
    Files::Node.create!(tenant: @tenant, drive: @drive, parent: @root, kind: :folder, name: "資料")

    assert_raises(ActiveRecord::RecordNotUnique) do
      Files::Node.create!(tenant: @tenant, drive: @drive, parent: @root, kind: :file, name: "資料")
    end
  end

  test "ゴミ箱の中の同名は重複とみなさない" do
    trashed = Files::Node.create!(
      tenant: @tenant, drive: @drive, parent: @root, kind: :file, name: "資料",
    )
    trashed.update!(deleted_at: Time.current, deleted_root_id: trashed.id)

    assert_nothing_raised do
      Files::Node.create!(tenant: @tenant, drive: @drive, parent: @root, kind: :file, name: "資料")
    end
  end

  test "共有ドライブは1テナントに1つ、個人ドライブは所有者ごとに1つ" do
    assert_raises(ActiveRecord::RecordNotUnique) do
      Files::Drive.create!(tenant: @tenant, kind: :shared)
    end

    Files::Drive.create!(tenant: @tenant, kind: :personal, owner: @member)
    assert_raises(ActiveRecord::RecordNotUnique) do
      Files::Drive.create!(tenant: @tenant, kind: :personal, owner: @member)
    end
  end

  test "ドライブの種別と所有者の組み合わせが守られる" do
    invalid = Files::Drive.new(tenant: @tenant, kind: :shared, owner: @member)
    assert_raises(ActiveRecord::StatementInvalid) { invalid.save!(validate: false) }
  end

  test "権限の対象はグループか個人のどちらか一方" do
    group = Group.create!(tenant: @tenant, name: "営業部")

    both = Files::Permission.new(
      tenant: @tenant, node: @root, group: group, tenant_user: @member, role: :viewer,
    )
    assert_raises(ActiveRecord::StatementInvalid) { both.save!(validate: false) }

    neither = Files::Permission.new(tenant: @tenant, node: @root, role: :viewer)
    assert_raises(ActiveRecord::StatementInvalid) { neither.save!(validate: false) }
  end

  test "同じノードの同じ主体に権限を二重に張れない" do
    group = Group.create!(tenant: @tenant, name: "営業部")
    Files::Permission.create!(tenant: @tenant, node: @root, group: group, role: :viewer)

    duplicate = Files::Permission.new(tenant: @tenant, node: @root, group: group, role: :editor)
    assert_raises(ActiveRecord::RecordNotUnique) { duplicate.save!(validate: false) }
  end

  test "「全員」グループはテナントに1つだけ" do
    assert_raises(ActiveRecord::RecordNotUnique) do
      Group.create!(tenant: @tenant, kind: :everyone, name: "全員2")
    end
  end

  test "同じ階層のグループ名は重複できない" do
    parent = Group.create!(tenant: @tenant, name: "営業部")
    Group.create!(tenant: @tenant, parent: parent, name: "1課")

    assert_raises(ActiveRecord::RecordNotUnique) do
      Group.create!(tenant: @tenant, parent: parent, name: "1課")
    end
    # トップレベル同士も重複できない（NULL 同士が別物にならないこと）
    assert_raises(ActiveRecord::RecordNotUnique) do
      Group.create!(tenant: @tenant, name: "営業部")
    end
  end

  test "フォルダは版を持てない" do
    version = Files::Version.create!(
      tenant: @tenant, node: @root, number: 1, byte_size: 10,
    )
    @root.current_version_id = version.id
    assert_raises(ActiveRecord::StatementInvalid) { @root.save!(validate: false) }
  end

  test "フォルダはサイズを持てない" do
    @root.byte_size = 100
    assert_raises(ActiveRecord::StatementInvalid) { @root.save!(validate: false) }
  end

  test "kind は型で値域が縛られる" do
    # 生の SQL が失敗するとトランザクションごと中断されるので、セーブポイントで囲む
    assert_raises(ActiveRecord::StatementInvalid) do
      Files::Node.transaction(requires_new: true) do
        Files::Node.connection.execute(<<~SQL)
          INSERT INTO files_nodes (tenant_id, drive_id, kind, name, byte_size, created_at, updated_at)
          VALUES ('#{@tenant.id}', #{@drive.id}, 'shortcut', 'x', 0, now(), now())
        SQL
      end
    end
  end

  test "版は番号で一意" do
    node = Files::Node.create!(tenant: @tenant, drive: @drive, parent: @root, kind: :file, name: "a.txt")
    Files::Version.create!(tenant: @tenant, node: node, number: 1, byte_size: 10)

    duplicate = Files::Version.new(tenant: @tenant, node: node, number: 1, byte_size: 20)
    assert_raises(ActiveRecord::RecordNotUnique) { duplicate.save!(validate: false) }
  end

  test "祖先の経路は作成時に設定される" do
    a = Files::Node.create!(tenant: @tenant, drive: @drive, parent: @root, kind: :folder, name: "a")
    b = Files::Node.create!(tenant: @tenant, drive: @drive, parent: a, kind: :file, name: "b.txt")

    assert_equal [], @root.reload.ancestor_ids
    assert_equal [@root.id, a.id], b.reload.ancestor_ids
    assert_equal [@root, a], b.ancestors
  end

  test "移動すると配下の経路も付け替わる" do
    a = Files::Node.create!(tenant: @tenant, drive: @drive, parent: @root, kind: :folder, name: "a")
    b = Files::Node.create!(tenant: @tenant, drive: @drive, parent: @root, kind: :folder, name: "b")
    child = Files::Node.create!(tenant: @tenant, drive: @drive, parent: a, kind: :folder, name: "c")
    grandchild = Files::Node.create!(tenant: @tenant, drive: @drive, parent: child, kind: :file, name: "d.txt")

    a.update_column(:parent_id, b.id)

    assert_equal [@root.id, b.id], a.reload.ancestor_ids
    assert_equal [@root.id, b.id, a.id], child.reload.ancestor_ids
    assert_equal [@root.id, b.id, a.id, child.id], grandchild.reload.ancestor_ids
  end

  test "経路を直接書き換えても親から求め直される" do
    a = Files::Node.create!(tenant: @tenant, drive: @drive, parent: @root, kind: :folder, name: "a")

    a.update_column(:ancestor_ids, [999])

    assert_equal [@root.id], a.reload.ancestor_ids
  end

  test "insert_all で作っても経路が設定される" do
    Files::Node.insert_all([{ tenant_id: @tenant.id, drive_id: @drive.id, parent_id: @root.id, kind: "file", name: "x" }])

    assert_equal [@root.id], Files::Node.find_by!(name: "x").ancestor_ids
  end

  test "自分の配下には移動できない" do
    a = Files::Node.create!(tenant: @tenant, drive: @drive, parent: @root, kind: :folder, name: "a")
    child = Files::Node.create!(tenant: @tenant, drive: @drive, parent: a, kind: :folder, name: "c")

    assert_raises(ActiveRecord::StatementInvalid) do
      Files::Node.transaction(requires_new: true) { a.update_column(:parent_id, child.id) }
    end
  end
end
