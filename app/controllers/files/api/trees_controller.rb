module Files
  module Api
    class TreesController < BaseController
      def show
        shared = Drive.shared.find_by(tenant: current_tenant)&.root
        personal = Drive.personal.find_by(owner: current_tenant_user)&.root
        tops = [shared, personal].compact.index_with { |root| root.children.kept.folder.order(:name).to_a }
        permissions = access.effective_permissions(tops.values.flatten)
        folders = tops.transform_values do |children|
          children.map { |node| { id: node.id, name: node.name, readable: permissions[node].readable? } }
        end

        render json: { shared_drive: folders.fetch(shared, []), my_drive: folders.fetch(personal, []) }
      end
    end
  end
end
