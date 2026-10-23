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
    @sales.replace_labels!(%w[営業 本部])
    assert_equal %w[営業 本部], @sales.labels.pluck(:name).sort

    @sales.replace_labels!(%w[本部 地域])
    assert_equal %w[地域 本部], @sales.labels.reload.pluck(:name).sort
    assert_equal %w[営業 地域 本部], GroupLabel.pluck(:name).sort
  end

  test "下位のグループの id を、停止中も含めて孫までたどる" do
    first = Group.create!(tenant: @tenant, parent: @sales, name: "1課")
    team = Group.create!(tenant: @tenant, parent: first, name: "1班")
    second = Group.create!(tenant: @tenant, parent: @sales, name: "2課")
    second.update_columns(suspended_at: Time.current, suspension_root_id: second.id, suspended_path: ["営業部"])

    assert_equal [first.id, team.id, second.id].sort, Group.descendant_ids_of(@sales.id).sort
    assert_empty Group.descendant_ids_of(team.id)
  end
end
