module Files
  module Api
    class FoldersController < BaseController
      def show
        folder =
          case params[:drive]
          when "shared" then Drive.shared_root(current_tenant)
          when "personal" then Drive.personal_root(current_tenant_user)
          else Node.kept.folder.find(params[:id])
          end
        permission = access.effective_permission(folder)
        raise ActiveRecord::RecordNotFound unless permission.readable?

        entries = folder.children.kept.includes(:creator).order(:kind, :name).to_a
        permissions = access.effective_permissions(entries)

        ancestors = folder.ancestors.to_a
        ancestor_permissions = access.effective_permissions(ancestors)
        breadcrumbs = ancestors.reverse.take_while { |node| ancestor_permissions[node].readable? }.reverse

        section =
          if folder.drive.shared? then :shared_drive
          elsif folder.drive.owner_id == current_tenant_user.id then :my_drive
          else :shared_with_me
          end

        render json: {
          folder: { id: folder.id, label: node_label(folder) },
          section: section,
          breadcrumbs: breadcrumbs.map { |node| { id: node.id, label: node_label(node) } },
          via_shared: breadcrumbs.size < ancestors.size,
          can_edit: permission.editable?,
          entries: entries.map { |node| entry_json(node, permissions[node].readable?) },
        }
      end

      def create
        parent = Node.kept.folder.find(params[:parent_id])
        permission = access.effective_permission(parent)
        raise ActiveRecord::RecordNotFound unless permission.readable?
        return head :forbidden unless permission.editable?

        folder = Node.create_folder!(parent: parent, name: params[:name], creator: current_tenant_user)
        render json: { id: folder.id, name: folder.name }, status: :created
      rescue ActiveRecord::RecordInvalid => e
        render json: { errors: e.record.errors.full_messages }, status: :unprocessable_content
      rescue ActiveRecord::RecordNotUnique
        # 同じ名前で同時に作られ、検証をすり抜けて DB の一意制約に当たったとき
        errors = ActiveModel::Errors.new(Node.new)
        errors.add(:name, :taken)
        render json: { errors: errors.full_messages }, status: :unprocessable_content
      end
    end
  end
end
