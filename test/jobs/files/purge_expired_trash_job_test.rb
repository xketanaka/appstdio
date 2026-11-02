require "test_helper"

class Files::PurgeExpiredTrashJobTest < ActiveJob::TestCase
  test "テナントごとに、purge_after を過ぎたものだけを完全に削除する" do
    tenants = ["テナントA", "テナントB"].map { Tenant.setup!(name: it) }
    expired, recent = tenants.map do |tenant|
      TenantContext.switch(tenant:) do
        root = Files::Drive.shared_root(tenant)
        [1.day.ago, 1.day.from_now].map do |purge_after|
          node = Files::Node.create!(tenant:, drive_id: root.drive_id, parent: root, kind: :folder, name: purge_after.to_s)
          node.update!(deleted_at: Time.current, deleted_root_id: node.id, purge_after:)
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
