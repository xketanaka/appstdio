require "test_helper"

class Files::PurgeUnattachedBlobsJobTest < ActiveJob::TestCase
  test "1日たっても登録されていない blob だけを消す" do
    old = ActiveStorage::Blob.create_and_upload!(io: StringIO.new("a"), filename: "old.txt")
    old.update_column(:created_at, 2.days.ago)
    recent = ActiveStorage::Blob.create_and_upload!(io: StringIO.new("b"), filename: "recent.txt")

    Files::PurgeUnattachedBlobsJob.perform_now

    assert_not ActiveStorage::Blob.exists?(old.id)
    assert_not old.service.exist?(old.key)
    assert ActiveStorage::Blob.exists?(recent.id)
  end
end
