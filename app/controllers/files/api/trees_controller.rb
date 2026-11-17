module Files
  module Api
    # 左ペインのツリー。show はドライブのルートと直下のフォルダ、グループドライブ・プロジェクトドライブの
    # ルート、テナントの使用量を、children は指定した親の直下のフォルダを返す。深い階層は、開いたときに
    # children で読む
    class TreesController < BaseController
      def show
        roots = {
          shared_drive: Drive.shared.find_by(tenant: current_tenant)&.root,
          my_drive: Drive.personal.find_by(owner: current_tenant_user)&.root,
        }
        folders = folders_under(roots.values.compact)

        # 所属するグループ（下位のグループのメンバーは上位にも属する）のドライブ。部署は使うにしたものだけ。
        # プロジェクトのドライブは、プロジェクト機能を利用していれば、初めて出すときに作る
        kinds = current_tenant.setting.projects_enabled? ? %w[department project] : %w[department]
        groups = Group.active.where(id: access.belonging_group_ids, kind: kinds)
        groups.project.where.not(id: Drive.where.not(group_id: nil).select(:group_id)).find_each { Drive.group_root(it) }
        group_roots = Node.where(parent_id: nil)
          .joins(:drive).merge(Drive.group_drive.where(disabled_at: nil, group_id: groups.select(:id)))
          .includes(drive: :group).to_a
        with_children = Node.kept.folder.where(parent_id: group_roots.map(&:id)).distinct.pluck(:parent_id).to_set
        roots_by_group = group_roots.index_by { it.drive.group_id }
        drive_entries = ->(kind) do
          Group.sort_by_name_path(group_roots.map { it.drive.group }.select { it.kind == kind }).map do |group, _|
            root = roots_by_group[group.id]
            { id: root.id, name: group.name, readable: true, has_children: with_children.include?(root.id) }
          end
        end

        setting = current_tenant.files_setting
        render json: {
          **roots.transform_values { |root| root && { id: root.id, folders: folders.fetch(root.id) } },
          group_drives: drive_entries.("department"),
          project_drives: drive_entries.("project"),
          storage: { used_bytes: setting.storage_used_bytes, limit_bytes: setting.storage_limit_bytes },
        }
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
