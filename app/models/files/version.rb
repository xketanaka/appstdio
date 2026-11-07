module Files
  class Version < ApplicationRecord
    has_one_attached :body

    belongs_to :tenant
    belongs_to :node, class_name: "Files::Node"
    belongs_to :creator, class_name: "TenantUser", optional: true

    validates :number, numericality: { only_integer: true, greater_than: 0 },
      uniqueness: { scope: :node_id }
    validates :byte_size, numericality: { greater_than_or_equal_to: 0 }
    validates :label, length: { maximum: 255 }, allow_nil: true

    scope :kept, -> { where(purged_at: nil) }

    # 保持日数を過ぎた古い版の中身を消す（doc/files.md の「版」）。日数は、その版が最新で
    # なくなった日（次の版ができた日）から数える。最新版には次の版が無いので、日数に関わらず残る
    def self.purge_expired!(tenant_id:, retention_days:)
      expired = kept.where(tenant_id:).where(<<~SQL.squish, retention_days.days.ago)
        EXISTS (
          SELECT 1 FROM files_versions next
          WHERE next.node_id = files_versions.node_id AND next.number = files_versions.number + 1
            AND next.created_at <= ?
        )
      SQL
      blob_ids = transaction { purge_bodies!(expired, tenant_id:) }
      ActiveStorage::Blob.unattached.where(id: blob_ids).find_each(&:purge_later)
    end

    # 中身を外して purged_at を付け、その大きさを使用量から引く。外した blob の id を返す。
    # トランザクションの中で呼び、blob は、ほかの版も指していないものだけをコミットのあとで消すこと
    # （「最新に戻す」で作った版は、古い版と blob を共有する）
    def self.purge_bodies!(versions, tenant_id:)
      # 同時に消されたものを二重に引かないよう、押さえてから purged_at を見直す
      ids = kept.where(id: versions.select(:id)).lock.ids
      attachments = ActiveStorage::Attachment.where(record_type: name, record_id: ids)
      blob_ids = attachments.pluck(:blob_id)

      Setting.where(tenant_id:)
        .update_all(["storage_used_bytes = GREATEST(storage_used_bytes - ?, 0)", where(id: ids).sum(:byte_size)])
      attachments.delete_all
      where(id: ids).update_all(purged_at: Time.current)
      blob_ids
    end
  end
end
