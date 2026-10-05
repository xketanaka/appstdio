module Files
  class Permission < ApplicationRecord
    # none は打ち消し。継承してきた権限をこのノードで無効にする。
    # 他の主体からの付与までは打ち消さない（拒否ではない）
    ROLES = %w[none viewer editor manager].freeze

    # none は ActiveRecord の none スコープと衝突するため接頭辞を付ける
    enum :role, ROLES.index_by(&:itself), prefix: :role, validate: true

    belongs_to :tenant
    belongs_to :node, class_name: "Files::Node"
    belongs_to :group, optional: true
    belongs_to :tenant_user, optional: true

    validate :exactly_one_subject
    validates :group_id, uniqueness: { scope: :node_id }, if: :group_id?
    validates :tenant_user_id, uniqueness: { scope: :node_id }, if: :tenant_user_id?

    def subject
      group || tenant_user
    end

    private

    def exactly_one_subject
      return if group_id.present? ^ tenant_user_id.present?

      errors.add(:base, :invalid)
    end
  end
end
