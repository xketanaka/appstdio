require "test_helper"

class GroupTest < ActiveSupport::TestCase
  setup do
    @tenant = Tenant.setup!(name: "テナントA")
    TenantContext.apply(tenant: @tenant)
    @sales = Group.create!(tenant: @tenant, name: "営業部")
  end

  teardown do
    TenantContext.clear
  end

  test "ラベルを名前で付け直し、外したラベルもテナントの一覧には残す" do
    assert @sales.save_with_labels(%w[営業 本部])
    assert_equal %w[営業 本部], @sales.labels.pluck(:name).sort

    assert @sales.save_with_labels(%w[本部 地域])
    assert_equal %w[地域 本部], @sales.labels.reload.pluck(:name).sort
    assert_equal %w[営業 地域 本部], GroupLabel.pluck(:name).sort
  end

  test "ラベルが保存できなければグループの保存も戻し、ラベルの誤りをグループの誤りとして出す" do
    group = Group.new(tenant: @tenant, name: "新しい部")

    assert_not group.save_with_labels(["あ" * 101])
    assert_not group.persisted?
    assert_not Group.exists?(name: "新しい部")
    assert_includes group.errors[:base].join, "100文字以内"
  end

  test "メンバーを付け直し、保存できない行があれば全部戻してグループの誤りとして出す" do
    users = %w[a b].map do |key|
      TenantUser.create!(tenant: @tenant, user: User.create!(email: "#{key}@example.com", password: "password1234"),
        display_name: key, status: :active)
    end
    assert @sales.replace_members(users[0].id => "leader")

    assert_not @sales.replace_members(users[0].id => "member", users[1].id => "owner")
    assert_equal({ users[0].id => "leader" }, @sales.group_members.pluck(:tenant_user_id, :role).to_h)
    assert_predicate @sales.errors[:base], :present?
  end

  test "下位のグループの id を、停止中も含めて孫までたどる" do
    first = Group.create!(tenant: @tenant, parent: @sales, name: "1課")
    team = Group.create!(tenant: @tenant, parent: first, name: "1班")
    second = Group.create!(tenant: @tenant, parent: @sales, name: "2課")
    second.update_columns(suspended_at: Time.current, suspension_root_id: second.id, suspended_path: ["営業部"])

    assert_equal [first.id, team.id, second.id].sort, Group.descendant_ids_of(@sales.id).sort
    assert_empty Group.descendant_ids_of(team.id)
  end

  test "利用停止は、起点と有効な下位に、その時点の上位の名前の並びと起点を書き込む" do
    first = Group.create!(tenant: @tenant, parent: @sales, name: "1課")
    team = Group.create!(tenant: @tenant, parent: first, name: "1班")
    company = Group.create!(tenant: @tenant, name: "全社")
    @sales.update!(parent: company)
    by = TenantUser.create!(tenant: @tenant, user: User.create!(email: "a@example.com", password: "password1234"),
      display_name: "Aさん", status: :active)

    @sales.suspend!(by:)

    [@sales, first, team].each(&:reload)
    assert_equal [@sales.id] * 3, [@sales, first, team].map(&:suspension_root_id)
    assert_equal [["全社"], %w[全社 営業部], %w[全社 営業部 1課]], [@sales, first, team].map(&:suspended_path)
    assert_equal [by.id] * 3, [@sales, first, team].map(&:suspended_by_id)
    assert_not company.reload.suspended?
  end

  test "先に停止していた下位は、上位を停止しても再開しても、その起点のまま残す" do
    first = Group.create!(tenant: @tenant, parent: @sales, name: "1課")
    team = Group.create!(tenant: @tenant, parent: first, name: "1班")
    second = Group.create!(tenant: @tenant, parent: @sales, name: "2課")
    by = TenantUser.create!(tenant: @tenant, user: User.create!(email: "a@example.com", password: "password1234"),
      display_name: "Aさん", status: :active)
    first.suspend!(by:)
    @sales.suspend!(by:)

    assert_equal [first.id, first.id, @sales.id], [first, team, second].map { it.reload.suspension_root_id }

    assert @sales.reactivate
    assert_not @sales.suspended?
    assert_not second.reload.suspended?
    assert_equal [first.id, first.id], [first, team].map { it.reload.suspension_root_id }
  end

  test "再開できるのは起点だけで、上位が停止中か、同じ名前の有効なグループがあると再開できない" do
    first = Group.create!(tenant: @tenant, parent: @sales, name: "1課")
    team = Group.create!(tenant: @tenant, parent: first, name: "1班")
    by = TenantUser.create!(tenant: @tenant, user: User.create!(email: "a@example.com", password: "password1234"),
      display_name: "Aさん", status: :active)
    first.suspend!(by:)
    @sales.suspend!(by:)

    assert_equal [:not_root, { name: "1課" }], team.reload.reactivation_blocker
    assert_equal [:ancestor_suspended, { name: "営業部" }], first.reload.reactivation_blocker
    assert_not first.reactivate

    assert @sales.reload.reactivate
    Group.create!(tenant: @tenant, parent: @sales, name: "1課")
    assert_equal [:name_taken, {}], first.reload.reactivation_blocker
  end
end
