module Files
  class Drive < ApplicationRecord
    enum :kind, { shared: "shared", personal: "personal" }, validate: true

    belongs_to :tenant
    belongs_to :owner, class_name: "TenantUser", optional: true
    has_many :nodes, class_name: "Files::Node", dependent: :destroy

    validates :owner_id, presence: true, if: :personal?
    validates :owner_id, absence: true, if: :shared?

    def root
      nodes.find_by(parent_id: nil)
    end
  end
end
