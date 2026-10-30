require "test_helper"

class TenantUserTest < ActiveSupport::TestCase
  setup do
    @tenant = Tenant.setup!(name: "テナントA")
    TenantContext.apply(tenant: @tenant)
    @sales = Group.create!(tenant: @tenant, name: "営業部")
    @dev = Group.create!(tenant: @tenant, name: "開発部")
  end

  teardown do
    TenantContext.clear
  end

  test "新しいメールアドレスなら User を作り、招待中として加えて、選んだグループに入れる" do
    tenant_user = TenantUser.invite(tenant: @tenant, email: " new@example.com ", group_ids: [@sales.id, @dev.id],
      display_name: "新人さん", role: "member")

    assert_empty tenant_user.errors
    assert tenant_user.invited?
    assert_equal "new@example.com", tenant_user.user.email
    assert_equal [@dev.id, @sales.id].sort, tenant_user.group_members.pluck(:group_id).sort
    assert tenant_user.group_members.all?(&:member?)
  end

  test "他のテナントにいる人は、その User に所属を足し、パスワードは変えない" do
    user = User.create!(email: "taro@example.com", password: "password1234")

    tenant_user = TenantUser.invite(tenant: @tenant, email: "TARO@example.com", display_name: "太郎さん", role: "admin")

    assert_empty tenant_user.errors
    assert_equal user, tenant_user.user
    assert tenant_user.admin?
    assert user.reload.authenticate("password1234")
  end

  test "このテナントにすでにいる人は加えない" do
    user = User.create!(email: "taro@example.com", password: "password1234")
    TenantUser.create!(tenant: @tenant, user:, display_name: "太郎さん", status: :suspended)

    tenant_user = TenantUser.invite(tenant: @tenant, email: "taro@example.com", display_name: "別の太郎さん", role: "member")

    assert_not tenant_user.persisted?
    assert_equal ["メールアドレスの利用者はすでに登録されています。"], tenant_user.errors.full_messages
    assert_equal 1, TenantUser.count
  end

  test "削除済みの人は、同じ行を招待中に戻す" do
    user = User.create!(email: "taro@example.com", password: "password1234")
    deleted = TenantUser.create!(tenant: @tenant, user:, display_name: "太郎さん", role: :admin, status: :deleted)

    tenant_user = TenantUser.invite(tenant: @tenant, email: "taro@example.com", group_ids: [@sales.id],
      display_name: "戻った太郎さん", role: "member")

    assert_empty tenant_user.errors
    assert_equal deleted.id, tenant_user.id
    assert_equal ["戻った太郎さん", "member", "invited"], deleted.reload.values_at(:display_name, :role, :status)
    assert_equal [@sales.id], tenant_user.group_members.pluck(:group_id)
  end

  test "メールアドレスと表示名の誤りをまとめて出し、何も作らない" do
    tenant_user = TenantUser.invite(tenant: @tenant, email: "not-an-email", group_ids: [@sales.id],
      display_name: "", role: "member")

    assert_includes tenant_user.errors.full_messages, "メールアドレスが不正な値です。"
    assert tenant_user.errors.of_kind?(:display_name, :blank)
    assert_not User.exists?(email: "not-an-email")
    assert_equal 0, GroupMember.count
  end

  test "停止中や「全員」のグループには入れられない" do
    @dev.suspend!(by: TenantUser.create!(tenant: @tenant, user: User.create!(email: "a@example.com", password: "password1234"),
      display_name: "管理者さん", role: :admin, status: :active))

    [@dev, Group.everyone_of(@tenant)].each do |group|
      assert_raises(ActiveRecord::RecordNotFound) do
        TenantUser.invite(tenant: @tenant, email: "new@example.com", group_ids: [group.id], display_name: "新人さん", role: "member")
      end
    end
    assert_not User.exists?(email: "new@example.com")
  end

  test "削除すると行は残して削除済みにし、グループからは外す" do
    user = User.create!(email: "taro@example.com", password: "password1234")
    tenant_user = TenantUser.create!(tenant: @tenant, user:, display_name: "太郎さん", status: :active)
    GroupMember.create!(tenant: @tenant, group: @sales, tenant_user:, role: :leader)

    tenant_user.mark_deleted!

    assert tenant_user.reload.deleted?
    assert_not GroupMember.exists?(tenant_user:)
  end

  test "オーナーと自分自身は削除できない" do
    owner, admin, member = [:owner, :admin, :member].map do |role|
      TenantUser.create!(tenant: @tenant, user: User.create!(email: "#{role}@example.com", password: "password1234"),
        display_name: role, role:, status: :active)
    end

    assert member.deletable_by?(admin)
    assert admin.deletable_by?(owner)
    assert_not owner.deletable_by?(admin)
    assert_not admin.deletable_by?(admin)
  end
end
