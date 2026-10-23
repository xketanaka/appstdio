module Files
  # ダイレクトアップロードで中身を送ったが、登録（files/api/nodes#upload）まで進まなかった blob を消す。
  # 送っている途中や送り終えた直後の分を消さないよう、1日たったものだけにする
  class PurgeUnattachedBlobsJob < ApplicationJob
    def perform
      ActiveStorage::Blob.unattached.where(created_at: ...1.day.ago).find_each(&:purge)
    end
  end
end
