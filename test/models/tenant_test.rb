require "test_helper"

class TenantTest < ActiveSupport::TestCase
  teardown do
    TenantContext.clear
  end

  describe "作成" do
    test "「全員」グループを作る" do
      tenant = Tenant.create!(name: "テナントA")

      TenantContext.switch(tenant: tenant) do
        assert_equal ["全員"], Group.everyone.pluck(:name)
      end
    end

    test "作成の前に設定していたコンテキストに戻す" do
      other = Tenant.create!(name: "テナントB")
      TenantContext.apply(tenant: other)

      Tenant.create!(name: "テナントA")

      assert_equal other.id, TenantContext.tenant_id
    end
  end
end
