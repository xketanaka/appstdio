module Files
  class Setting < ApplicationRecord
    belongs_to :tenant

    validates :tenant_id, uniqueness: true
    validates :storage_limit_bytes, numericality: { greater_than: 0 }
    validates :version_retention_days,
      numericality: { greater_than: 0 }, allow_nil: true

    def remaining_bytes
      storage_limit_bytes - storage_used_bytes
    end

    def usage_ratio
      return 0.0 if storage_limit_bytes.zero?

      storage_used_bytes.to_f / storage_limit_bytes
    end
  end
end
