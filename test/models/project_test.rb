require "test_helper"

class ProjectTest < ActiveSupport::TestCase
  setup do
    @tenant = Tenant.setup!(name: "テナントA")
    TenantContext.apply(tenant: @tenant)
    @owner = TenantUser.create!(tenant: @tenant, user: User.create!(email: "o@example.com", password: "password1234"),
      display_name: "オーナー", role: :owner, status: :active)
  end

  teardown do
    TenantContext.clear
  end

  def create_project(name, labels: [])
    Project.build(tenant: @tenant).tap { assert it.save_with(name:, label_names: labels) }
  end

  test "作ると、最上位の「プロジェクト」の下にグループを作り、ラベルを付ける" do
    project = create_project("新製品開発", labels: %w[社外])

    assert project.group.project?
    assert project.group.parent.project_root?
    assert_equal "プロジェクト", project.group.parent.name
    assert_equal "新製品開発", project.name
    assert_equal %w[社外], project.labels.pluck(:name)
    assert_equal 1, Group.project_root.count

    create_project("社内改善")
    assert_equal 1, Group.project_root.count
  end

  test "有効なプロジェクトどうしで名前は重ならず、誤りはプロジェクト名として出す" do
    create_project("新製品開発")

    project = Project.build(tenant: @tenant)
    assert_not project.save_with(name: "新製品開発", label_names: [])
    assert_includes project.errors.full_messages, "プロジェクト名が他のプロジェクトと重複しています。"
    assert_not project.persisted?
    assert_equal 1, Group.project.count
  end

  test "ラベルの誤りで保存できなければ、グループもプロジェクトも作らない" do
    project = Project.build(tenant: @tenant)

    assert_not project.save_with(name: "新製品開発", label_names: ["あ" * 256])
    assert_not_empty project.errors[:base]
    assert_equal 0, Group.project.count
    assert_equal 0, Project.count
  end

  test "利用停止・再開はグループに対して行い、名前が重なる有効なプロジェクトがあれば再開できない" do
    project = create_project("新製品開発")

    project.suspend!(by: @owner)
    assert project.reload.suspended?
    assert_equal [project], Project.suspended.to_a
    create_project("新製品開発")

    assert_equal [:name_taken, {}], project.reactivation_blocker
    assert_not project.reactivate
  end

  test "削除するとグループも消える" do
    project = create_project("新製品開発")

    project.destroy_with_group!

    assert_equal 0, Project.count
    assert_equal 0, Group.project.count
  end

  test "最上位の「プロジェクト」と同じ名前の部署が最上位にあると、作れない" do
    Group.create!(tenant: @tenant, name: "プロジェクト")

    assert_raises(ActiveRecord::RecordInvalid) { Group.project_root_of!(@tenant) }
  end

  test "プロジェクトのグループの下や、「プロジェクト」の下には部署を置けず、プロジェクトのグループは「プロジェクト」の直下にだけ置ける" do
    project = create_project("新製品開発")
    root = project.group.parent

    assert_not Group.new(tenant: @tenant, name: "チーム", parent: project.group).valid?
    assert_not Group.new(tenant: @tenant, name: "チーム", parent: root).valid?
    assert_not Group.new(tenant: @tenant, kind: :project, name: "直下でない", parent: Group.create!(tenant: @tenant, name: "営業部")).valid?
    assert_not Group.new(tenant: @tenant, kind: :project, name: "最上位").valid?
  end
end
