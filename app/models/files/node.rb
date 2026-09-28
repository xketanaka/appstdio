module Files
  class Node < ApplicationRecord
    enum :kind, { folder: "folder", file: "file" }, validate: true

    belongs_to :tenant
    belongs_to :drive, class_name: "Files::Drive"
    belongs_to :parent, class_name: "Files::Node", optional: true
    belongs_to :creator, class_name: "TenantUser", optional: true
    belongs_to :current_version, class_name: "Files::Version", optional: true
    belongs_to :deleted_root, class_name: "Files::Node", optional: true
    belongs_to :deleted_by, class_name: "TenantUser", optional: true

    has_many :children, class_name: "Files::Node", foreign_key: :parent_id, dependent: :destroy
    has_many :versions, class_name: "Files::Version", dependent: :destroy
    has_many :permissions, class_name: "Files::Permission", dependent: :destroy

    scope :kept, -> { where(deleted_at: nil) }
    scope :trashed, -> { where.not(deleted_at: nil).where(purged_at: nil) }
    # ゴミ箱に並べるのは削除操作の起点だけ。中身は展開しない
    scope :trash_roots, -> { trashed.where("id = deleted_root_id") }

    validates :name, presence: true, length: { maximum: 255 }
    validates :name, exclusion: { in: [".", ".."] }
    validates :name, format: { without: %r{/} }

    def root?
      parent_id.nil?
    end

    # 自身から根まで。権限の解決に使う
    def self_and_ancestors
      chain = [self]
      node = parent
      while node && chain.exclude?(node)
        chain << node
        node = node.parent
      end
      chain
    end
  end
end
