module Files
  class Activity < ApplicationRecord
    ACTIONS = %w[created updated renamed moved deleted restored purged shared].freeze

    enum :action, ACTIONS.index_by(&:itself), validate: true

    belongs_to :tenant
    belongs_to :node, class_name: "Files::Node", optional: true
    belongs_to :actor, class_name: "TenantUser", optional: true

    # 追記だけの記録なので updated_at を持たない
    self.record_timestamps = false

    before_create { self.created_at ||= Time.current }
  end
end
