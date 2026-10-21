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
    scope :trash_roots, -> { trashed.where("id = deleted_root_id") }

    validates :name, presence: true, length: { maximum: 255 }
    validates :current_version_id, absence: true, if: :folder?
    validates :byte_size, numericality: { equal_to: 0 }, if: :folder?
    validates :name, exclusion: { in: [".", ".."] }
    validates :name, format: { without: %r{/} }
    # ゴミ箱の中のものとは重複してよい。DB の一意制約（deleted_at IS NULL の部分インデックス）と揃える
    validates :name, uniqueness: { scope: :parent_id, conditions: -> { kept } }, if: :parent_id?

    # 作った人を管理者にして、操作履歴を残す（doc/files.md の「権限の継承」「操作履歴」）
    def self.create_folder!(parent:, name:, creator:)
      transaction do
        folder = create!(
          tenant_id: parent.tenant_id, drive_id: parent.drive_id, parent:, kind: :folder,
          name: name.to_s.strip, creator:,
        )
        Permission.create!(tenant_id: folder.tenant_id, node: folder, tenant_user: creator, role: :manager)
        Activity.create!(tenant_id: folder.tenant_id, node: folder, actor: creator, action: :created)
        folder
      end
    end

    def root?
      parent_id.nil?
    end

    # ancestor_ids はトリガが書くので、保存直後のインスタンスが持つ値は古い
    def ancestors
      ids = self.class.where(id: id).pick(:ancestor_ids)
      self.class.where(id: ids).in_order_of(:id, ids)
    end
  end
end
