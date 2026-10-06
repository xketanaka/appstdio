module Files
  class BaseController < ApplicationController
    layout "files"

    helper_method :tree, :node_label

    private

    def access
      @access ||= Access.new(current_tenant_user)
    end

    # 描画時に呼ぶ。アクションの中でドライブを作った場合も反映される
    def tree
      @tree ||= begin
        shared = Drive.shared.find_by(tenant: current_tenant)&.root
        personal = Drive.personal.find_by(owner: current_tenant_user)&.root
        tops = [shared, personal].compact.index_with { |root| root.children.kept.folder.order(:name).to_a }
        roles = access.roles(tops.values.flatten)
        folders = tops.transform_values { |children| children.map { |node| [node, roles.key?(node.id)] } }

        [
          { key: :shared_drive, path: files_root_path, folders: folders.fetch(shared, []) },
          { key: :shared_with_me, path: files_shared_items_path },
          { key: :my_drive, path: files_my_drive_path, folders: folders.fetch(personal, []) },
          { key: :trash, path: files_trash_path },
        ]
      end
    end

    def node_label(node)
      return node.name unless node.root?

      if node.drive.shared?
        t("files.drives.shared")
      elsif node.drive.owner_id == current_tenant_user.id
        t("files.drives.mine")
      else
        t("files.drives.others", name: node.drive.owner.display_name)
      end
    end
  end
end
