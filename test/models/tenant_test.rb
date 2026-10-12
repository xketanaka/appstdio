require "test_helper"

class TenantTest < ActiveSupport::TestCase
  teardown do
    TenantContext.clear
  end

  describe ".setup!" do
    test "「全員」グループを作る" do
      tenant = Tenant.setup!(name: "テナントA")

      TenantContext.switch(tenant: tenant) do
        assert_equal ["全員"], Group.everyone.pluck(:name)
      end
    end

    test "組織設定とファイル管理の設定の行を作り、ファイル管理は使う状態にする" do
      tenant = Tenant.setup!(name: "テナントA")

      TenantContext.switch(tenant: tenant) do
        assert_predicate tenant.setting, :present?
        assert_predicate tenant.files_setting, :enabled?
      end
    end

    test "作成の前に設定していたコンテキストに戻す" do
      other = Tenant.setup!(name: "テナントB")
      TenantContext.apply(tenant: other)

      Tenant.setup!(name: "テナントA")

      assert_equal other.id, TenantContext.tenant_id
    end
  end
end
