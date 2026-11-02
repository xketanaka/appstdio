require "test_helper"

class Files::PurgeExpiredTrashJobTest < ActiveJob::TestCase
  test "テナントごとに、ゴミ箱に入れて3ヶ月たったものだけを完全に削除する" do
    tenants = ["テナントA", "テナントB"].map { Tenant.setup!(name: it) }
    expired, recent = tenants.map do |tenant|
      TenantContext.switch(tenant:) do
        root = Files::Drive.shared_root(tenant)
        [(3.months + 1.day).ago, (3.months - 1.day).ago].map do |deleted_at|
          node = Files::Node.create!(tenant:, drive_id: root.drive_id, parent: root, kind: :folder, name: deleted_at.to_s)
          node.update!(deleted_at:, deleted_root_id: node.id)
          node
        end
      end
    end.transpose

    Files::PurgeExpiredTrashJob.perform_now

    TenantContext.switch(tenant: tenants.first) do
      assert_not_nil expired.first.reload.purged_at
      assert_nil recent.first.reload.purged_at
    end
    TenantContext.switch(tenant: tenants.last) { assert_not_nil expired.last.reload.purged_at }
  end
end
