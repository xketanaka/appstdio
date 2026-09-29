module Files
  class Version < ApplicationRecord
    # 実体はノードではなく版に添付する。上書きが行の追加になる
    has_one_attached :body

    belongs_to :tenant
    belongs_to :node, class_name: "Files::Node"
    belongs_to :creator, class_name: "TenantUser", optional: true

    validates :number, numericality: { only_integer: true, greater_than: 0 },
      uniqueness: { scope: :node_id }
    validates :byte_size, numericality: { greater_than_or_equal_to: 0 }
    validates :label, length: { maximum: 255 }, allow_nil: true

    scope :kept, -> { where(purged_at: nil) }
  end
end
