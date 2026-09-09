require "test_helper"

# appstdio_app ロールで接続していることが前提。前提そのものは
# RlsConfigurationTest で担保している。
class RowLevelSecurityTest < ActiveSupport::TestCase
  setup do
    @tenant_a = Tenant.create!(name: "テナントA")
    @tenant_b = Tenant.create!(name: "テナントB")
    @user_a = User.create!(email: "a@example.com", password: "password1234")
    @user_b = User.create!(email: "b@example.com", password: "password1234")

    @membership_a = TenantContext.switch(tenant: @tenant_a) do
      TenantUser.create!(tenant: @tenant_a, user: @user_a, display_name: "Aさん", status: :active)
    end
    @membership_b = TenantContext.switch(tenant: @tenant_b) do
      TenantUser.create!(tenant: @tenant_b, user: @user_b, display_name: "Bさん", status: :active)
    end
  end

  teardown do
    TenantContext.clear
  end

  test "テナントのコンテキストでは自テナントの所属情報しか見えない" do
    TenantContext.switch(tenant: @tenant_a) do
      assert_equal [@membership_a.id], TenantUser.pluck(:id)
    end

    TenantContext.switch(tenant: @tenant_b) do
      assert_equal [@membership_b.id], TenantUser.pluck(:id)
    end
  end

  test "コンテキストが未設定なら1件も見えない" do
    TenantContext.clear

    assert_equal 0, TenantUser.count
    assert_nil TenantUser.find_by(id: @membership_a.id)
  end

  test "ユーザコンテキストだけでも自分自身の所属は参照できる" do
    # ログイン直後、テナントを選ぶ前に所属テナント一覧を出すための経路
    TenantContext.switch(user: @user_a) do
      assert_equal [@tenant_a.id], TenantUser.pluck(:tenant_id)
    end
  end

  test "コンテキスト外のテナントの行は作成できない" do
    user = User.create!(email: "c@example.com", password: "password1234")

    error = assert_raises(ActiveRecord::StatementInvalid) do
      TenantContext.switch(tenant: @tenant_a) do
        TenantUser.create!(tenant: @tenant_b, user: user, display_name: "なりすまし")
      end
    end
    assert_match(/row-level security/, error.message)
  end

  test "他テナントの行は更新できない" do
    TenantContext.switch(tenant: @tenant_a) do
      assert_equal 0, TenantUser.where(id: @membership_b.id).update_all(display_name: "改ざん")
    end

    TenantContext.switch(tenant: @tenant_b) do
      assert_equal "Bさん", @membership_b.reload.display_name
    end
  end

  test "他テナントの行は削除できない" do
    TenantContext.switch(tenant: @tenant_a) do
      assert_equal 0, TenantUser.where(id: @membership_b.id).delete_all
    end

    TenantContext.switch(tenant: @tenant_b) do
      assert @membership_b.reload.persisted?
    end
  end

  test "自テナントの行を他テナントへ付け替えられない" do
    error = assert_raises(ActiveRecord::StatementInvalid) do
      TenantContext.switch(tenant: @tenant_a) do
        @membership_a.update!(tenant: @tenant_b)
      end
    end
    assert_match(/row-level security/, error.message)
  end
end
