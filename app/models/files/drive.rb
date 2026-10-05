module Files
  class Drive < ApplicationRecord
    enum :kind, { shared: "shared", personal: "personal" }, validate: true

    belongs_to :tenant
    belongs_to :owner, class_name: "TenantUser", optional: true
    has_many :nodes, class_name: "Files::Node", dependent: :destroy

    validates :owner_id, presence: true, if: :personal?
    validates :owner_id, absence: true, if: :shared?

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

    def root
      nodes.find_by(parent_id: nil)
    end
  end
end
