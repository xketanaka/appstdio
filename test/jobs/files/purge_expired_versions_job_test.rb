require "test_helper"

class Files::PurgeExpiredVersionsJobTest < ActiveJob::TestCase
  test "保持日数を決めたテナントだけ、古い版の中身を消す" do
    limited, unlimited = ["テナントA", "テナントB"].map { Tenant.setup!(name: it) }
    versions = [limited, unlimited].map do |tenant|
      TenantContext.switch(tenant:) do
        tenant.files_setting.update!(version_retention_days: 30) if tenant == limited
        root = Files::Drive.shared_root(tenant)
        user = User.create!(email: "#{tenant.id}@example.com", password: "password1234")
        member = TenantUser.create!(tenant:, user:, display_name: "利用者", status: :active)
        file = travel_to(60.days.ago) do
          Files::Node.create_file!(parent: root, blob:, creator: member)
            .tap { it.add_version!(blob:, creator: member) }
        end
        file.versions.find_by!(number: 1)
      end
    end

    Files::PurgeExpiredVersionsJob.perform_now

    TenantContext.switch(tenant: limited) { assert_predicate versions.first.reload.purged_at, :present? }
    TenantContext.switch(tenant: unlimited) { assert_nil versions.last.reload.purged_at }
  end

  def blob
    ActiveStorage::Blob.create_and_upload!(io: StringIO.new("中身"), filename: "見積.txt")
  end
end
