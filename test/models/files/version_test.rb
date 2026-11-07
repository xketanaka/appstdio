require "test_helper"

class Files::VersionTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  setup do
    @tenant = Tenant.setup!(name: "テナントA")
    user = User.create!(email: "a@example.com", password: "password1234")
    TenantContext.apply(tenant: @tenant)
    @member = TenantUser.create!(tenant: @tenant, user: user, display_name: "Aさん", status: :active)
    @root = Files::Drive.shared_root(@tenant)
  end

  teardown do
    TenantContext.clear
  end

  describe ".purge_expired!" do
    setup do
      @file = travel_to(100.days.ago) { Files::Node.create_file!(parent: @root, blob: blob("版1"), creator: @member) }
      travel_to(40.days.ago) { @file.add_version!(blob: blob("版2です"), creator: @member) }
      travel_to(10.days.ago) { @file.add_version!(blob: blob("版3"), creator: @member) }
    end

    test "最新でなくなってから保持日数を過ぎた版だけ、中身を消して使用量から引く" do
      v1, v2, v3 = @file.versions.order(:number).to_a
      v1_blob = v1.body.blob
      used = @tenant.files_setting.reload.storage_used_bytes

      perform_enqueued_jobs { Files::Version.purge_expired!(tenant_id: @tenant.id, retention_days: 30) }

      assert_equal [true, false, false], [v1, v2, v3].map { it.reload.purged_at.present? },
        "版2は作られて40日たつが、最新でなくなってからは10日なので残す"
      assert_not v1.body.attached?
      assert_not ActiveStorage::Blob.exists?(v1_blob.id)
      assert_equal used - v1.byte_size, @tenant.files_setting.reload.storage_used_bytes
    end

    test "最新版は、日数に関わらず残す" do
      perform_enqueued_jobs { Files::Version.purge_expired!(tenant_id: @tenant.id, retention_days: 1) }

      assert_equal [true, true, false], @file.versions.order(:number).map { it.purged_at.present? }
      assert_equal "版3", @file.reload.current_version.body.download.force_encoding("UTF-8")
    end

    test "最新の版と中身を共有している古い版は、消しても中身を残す" do
      v1 = @file.versions.find_by!(number: 1)
      @file.add_version!(blob: v1.body.blob, creator: @member, restored_from: 1)

      perform_enqueued_jobs { Files::Version.purge_expired!(tenant_id: @tenant.id, retention_days: 30) }

      assert_predicate v1.reload.purged_at, :present?
      assert_equal "版1", @file.reload.current_version.body.download.force_encoding("UTF-8")
    end
  end

  def blob(content)
    ActiveStorage::Blob.create_and_upload!(io: StringIO.new(content), filename: "見積.txt")
  end
end
