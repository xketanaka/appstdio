module Files
  module Api
    # 左ペインのツリー。show はドライブのルートと直下のフォルダを、children は指定した親の直下の
    # フォルダを返す。深い階層は、開いたときに children で読む
    class TreesController < BaseController
      def show
        roots = {
          shared_drive: Drive.shared.find_by(tenant: current_tenant)&.root,
          my_drive: Drive.personal.find_by(owner: current_tenant_user)&.root,
        }
        folders = folders_under(roots.values.compact)

        render json: roots.transform_values { |root| root && { id: root.id, folders: folders.fetch(root.id) } }
      end

      # 閲覧できないフォルダの中は返さない。一覧と同じく、開けないフォルダの中身は見せない
      def children
        parents = Node.kept.folder.where(id: Array(params[:parent_ids])).to_a
        permissions = access.effective_permissions(parents)

        render json: folders_under(parents.select { permissions[it].readable? })
      end

      private

      # 親の id ごとに、直下のフォルダを名前の順で返す。▸ を出すかを決めるため、
      # 開けるフォルダには子のフォルダがあるかも付ける
      def folders_under(parents)
        folders = Node.kept.folder.where(parent_id: parents.map(&:id)).order(:name).to_a
        permissions = access.effective_permissions(folders)
        with_children = Node.kept.folder.where(parent_id: folders.map(&:id)).distinct.pluck(:parent_id).to_set

        grouped = folders.group_by(&:parent_id)
        parents.to_h do |parent|
          entries = grouped.fetch(parent.id, []).map do |node|
            readable = permissions[node].readable?
            { id: node.id, name: node.name, readable:, has_children: readable && with_children.include?(node.id) }
          end
          [parent.id, entries]
        end
      end
    end
  end
end
