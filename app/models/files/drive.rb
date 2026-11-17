module Files
  class Drive < ApplicationRecord
    # キーを group にすると、Active Record の group（GROUP BY）とぶつかる
    enum :kind, { shared: "shared", personal: "personal", group_drive: "group" }, validate: true

    belongs_to :tenant
    belongs_to :owner, class_name: "TenantUser", optional: true
    # グループを消すと nil になる（中身は完全削除して、行だけ残る）
    belongs_to :group, optional: true
    has_many :nodes, class_name: "Files::Node", dependent: :destroy

    validates :owner_id, presence: true, if: :personal?
    validates :owner_id, absence: true, unless: :personal?

    # 中身をだれにも見せないグループドライブ（doc/files.md の「グループドライブ」）。
    # 使わないにしたもの、グループが利用停止中のもの、グループが消えたもの
    scope :unavailable, -> {
      group_drive.where("files_drives.disabled_at IS NOT NULL OR files_drives.group_id IS NULL")
        .or(group_drive.where(group_id: Group.suspended.select(:id)))
    }

    # 組織共有ドライブのルート。無ければ「全員=閲覧者」を付けて作る
    def self.shared_root(tenant)
      create_root(tenant: tenant, kind: :shared) do |root|
        root.permissions.create!(tenant: tenant, group: Group.everyone_of(tenant), role: :viewer)
      end
    end

    # マイドライブのルート。無ければ本人を管理者にして作る
    def self.personal_root(tenant_user)
      create_root(tenant: tenant_user.tenant, kind: :personal, owner: tenant_user) do |root|
        root.permissions.create!(tenant: tenant_user.tenant, tenant_user: tenant_user, role: :manager)
      end
    end

    # グループドライブのルート。無ければ「そのグループ=編集者」を付けて作る。使わないにしたものもそのまま返す。
    # グループ管理者を管理者として扱うのは、権限の行ではなく判定のとき（Files::Access）
    def self.group_root(group)
      create_root(tenant: group.tenant, kind: :group_drive, group:) do |root|
        root.permissions.create!(tenant: group.tenant, group:, role: :editor)
      end
    end

    # 部署のグループドライブを使うようにする。使わないにしていたものは、中身ごと元どおり見えるようになる
    def self.enable_for!(group)
      group_root(group).drive.update!(disabled_at: nil)
    end

    # グループを消すとき、そのドライブの中身をすべて完全削除する（ゴミ箱の完全削除と同じく、行は残す）。
    # 消した版の blob の id を返すので、トランザクションを抜けてから消すこと
    def self.purge_contents!(drives, tenant_id:)
      now = Time.current
      nodes = Node.where(drive_id: drives.select(:id), purged_at: nil)
      blob_ids = Version.purge_bodies!(Version.where(node_id: nodes.select(:id)), tenant_id:)
      nodes.update_all(["deleted_at = COALESCE(deleted_at, ?), purged_at = ?", now, now])
      blob_ids
    end

    def self.create_root(**attributes)
      drive = find_by(attributes)
      return drive.root if drive

      transaction(requires_new: true) do
        drive = create!(attributes)
        root = drive.nodes.create!(tenant: drive.tenant, kind: :folder, name: "root")
        yield root
        root
      end
    rescue ActiveRecord::RecordNotUnique
      find_by!(attributes).root
    end
    private_class_method :create_root

    # 使わないにする。trash なら直下のものをゴミ箱へ入れる（3ヶ月後に自動で完全削除される）
    def disable!(actor:, trash:)
      transaction do
        update!(disabled_at: Time.current)
        Node.trash!(root.children.kept.to_a, actor:) if trash
      end
    end

    def root
      nodes.find_by(parent_id: nil)
    end
  end
end
