module Files
  class Node < ApplicationRecord
    # 移動・復元など、まとめて行う操作ができなかった理由。messages はそのまま画面に出せる文
    class OperationError < StandardError
      attr_reader :messages

      def initialize(messages)
        @messages = messages
        super(messages.join(" "))
      end
    end

    class StorageFullError < StandardError; end

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

    # アップロードしたファイルを登録する。容量を数え、版1を作り、作った人を管理者にして、
    # 操作履歴を残す。容量が足りなければ StorageFullError（何も残さない）
    def self.create_file!(parent:, blob:, creator:)
      transaction do
        # 同時に上げても上限を超えないよう、足せるときだけ1つの UPDATE で足す
        reserved = Setting.where(tenant_id: parent.tenant_id)
          .where("storage_used_bytes + ? <= storage_limit_bytes", blob.byte_size)
          .update_all(["storage_used_bytes = storage_used_bytes + ?", blob.byte_size])
        raise StorageFullError if reserved.zero?

        file = create!(
          tenant_id: parent.tenant_id, drive_id: parent.drive_id, parent:, kind: :file,
          name: blob.filename.to_s, byte_size: blob.byte_size, creator:,
        )
        version = Version.create!(
          tenant_id: file.tenant_id, node: file, number: 1, byte_size: blob.byte_size,
          content_type: blob.content_type, creator:, body: blob,
        )
        file.update!(current_version: version)
        Permission.create!(tenant_id: file.tenant_id, node: file, tenant_user: creator, role: :manager)
        Activity.create!(tenant_id: file.tenant_id, node: file, actor: creator, action: :created)
        file
      end
    end

    # 1件でも移せなければ何も動かさない（doc/files.md の「移動」）。権限は呼び出し側で確かめておくこと。
    # 移した先のドライブ・ancestor_ids は、配下の分も含めてトリガが付け替える
    def self.move!(nodes, to:, actor:)
      errors = ActiveModel::Errors.new(new)
      nodes.each do |node|
        errors.add(:base, :move_into_itself, name: node.name) if node.id == to.id || to.ancestor_ids.include?(node.id)
      end
      moving = nodes.reject { |node| node.parent_id == to.id }
      names = moving.map(&:name)
      taken = to.children.kept.where(name: names).pluck(:name) + names.tally.select { |_, count| count > 1 }.keys
      taken.uniq.each { |name| errors.add(:base, :name_taken_at_destination, name:) }
      raise OperationError, errors.full_messages if errors.any?

      transaction do
        moving.each do |node|
          from = node.parent_id
          node.update!(parent: to)
          Activity.create!(
            tenant_id: node.tenant_id, node:, actor:, action: :moved, detail: { from:, to: to.id },
          )
        end
      end
    end

    # ゴミ箱へ入れる。フォルダは配下もまとめて入れる（配下だけを URL で開けないように）。
    # 配下には deleted_root_id で、どの削除で入ったかを持たせ、復元のときにまとめて戻す
    def self.trash!(nodes, actor:)
      now = Time.current
      transaction do
        # フォルダとその中のものを一緒に選んだときは、フォルダの削除で中も入るので、浅いほうから処理する
        nodes.sort_by { it.ancestor_ids.size }.each do |node|
          next if kept.where(id: node.id).none?

          kept.where("? = ANY(ancestor_ids)", node.id).update_all(deleted_at: now, deleted_root_id: node.id, deleted_by_id: actor.id)
          node.update!(deleted_at: now, deleted_root_id: node.id, deleted_by: actor, purge_after: now + 3.months)
          Activity.create!(tenant_id: node.tenant_id, node:, actor:, action: :deleted)
        end
      end
    end

    # ゴミ箱から元の場所へ戻す。元のフォルダもゴミ箱にある・同じ名前のものができている場合は、
    # 1件も戻さずに理由を返す（doc/files.md の「ゴミ箱」）
    def self.restore!(nodes, actor:)
      errors = ActiveModel::Errors.new(new)
      nodes.each do |node|
        if node.parent.deleted_at
          errors.add(:base, :restore_parent_trashed, name: node.name, parent: node.parent.name)
        elsif node.parent.children.kept.exists?(name: node.name)
          errors.add(:base, :restore_name_taken, name: node.name)
        end
      end
      nodes.group_by { [it.parent_id, it.name] }.each_value do |same|
        errors.add(:base, :restore_name_taken, name: same.first.name) if same.size > 1
      end
      raise OperationError, errors.full_messages.uniq if errors.any?

      transaction do
        nodes.each do |node|
          where(deleted_root_id: node.id).update_all(deleted_at: nil, deleted_root_id: nil, deleted_by_id: nil, purge_after: nil)
          Activity.create!(tenant_id: node.tenant_id, node:, actor:, action: :restored)
        end
      end
    end

    def rename!(new_name, actor:)
      from = name
      update!(name: new_name.to_s.strip)
      return if name == from

      Activity.create!(tenant_id:, node: self, actor:, action: :renamed, detail: { from:, to: name })
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
