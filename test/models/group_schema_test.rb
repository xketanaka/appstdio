require "test_helper"

# グループ管理のテーブルの制約。バリデーションを迂回して DB の守りを確かめる
class GroupSchemaTest < ActiveSupport::TestCase
  setup do
    @tenant = Tenant.setup!(name: "テナントA")
    TenantContext.apply(tenant: @tenant)
    @sales = Group.create!(tenant: @tenant, name: "営業部")
  end

  teardown do
    TenantContext.clear
  end

  # DB に拒まれると、包まないとテストのトランザクションごと中断される
  def assert_rejected(error, &)
    assert_raises(error) { Group.transaction(requires_new: true, &) }
  end

  def suspend(group)
    group.update_columns(suspended_at: Time.current, suspension_root_id: group.id, suspended_path: [])
  end

  test "利用停止中のグループとは同じ名前で作れる。有効なグループ同士は重複できない" do
    first = Group.create!(tenant: @tenant, parent: @sales, name: "1課")
    suspend(first)
    suspend(@sales)

    assert_nothing_raised { Group.create!(tenant: @tenant, name: "営業部") }
    # 停止中の下には検証で作れないので、検証を通さずに入れる
    Group.new(tenant: @tenant, parent: @sales, name: "1課").save!(validate: false)
    assert_raises(ActiveRecord::RecordNotUnique) do
      Group.new(tenant: @tenant, parent: @sales, name: "1課").save!(validate: false)
    end
  end

  test "停止の日時・起点・上位の名前の並びは、そろって入るかそろって空" do
    assert_rejected(ActiveRecord::StatementInvalid) do
      @sales.update_columns(suspended_at: Time.current)
    end
  end

  test "グループのメンバーの役割はメンバーかグループ管理者" do
    user = User.create!(email: "a@example.com", password: "password1234")
    member = TenantUser.create!(tenant: @tenant, user:, display_name: "Aさん", status: :active)
    record = GroupMember.create!(tenant: @tenant, group: @sales, tenant_user: member)

    assert_predicate record, :member?
    assert_rejected(ActiveRecord::StatementInvalid) { record.update_column(:role, "owner") }
  end

  test "ラベルの名前はテナントの中で重複できず、同じグループに同じラベルは1回だけ付く" do
    label = GroupLabel.create!(tenant: @tenant, name: "営業")
    assert_rejected(ActiveRecord::RecordNotUnique) do
      GroupLabel.insert_all!([{ tenant_id: @tenant.id, name: "営業" }])
    end

    GroupLabeling.create!(tenant: @tenant, group: @sales, group_label: label)
    assert_rejected(ActiveRecord::RecordNotUnique) do
      GroupLabeling.insert_all!([{ tenant_id: @tenant.id, group_id: @sales.id, group_label_id: label.id }])
    end
  end
end
