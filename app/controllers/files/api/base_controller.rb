module Files
  module Api
    class BaseController < Files::BaseController
      rescue_from(ActiveRecord::RecordNotFound) { head :not_found }

      private

      # 画面と違ってログイン画面などへ転送しない。転送先の HTML を JSON として受け取らせないため。
      # Vue の側はページを読み直し、転送は入れ物のページに任せる
      def login_required
        head :unauthorized unless logged_in?
      end

      def tenant_required
        head :unauthorized if current_tenant_user.blank?
      end

      def render_not_found
        head :not_found
      end

      def access
        @access ||= Access.new(current_tenant_user, privileged: privileged_mode?)
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

      # 閲覧できない項目は名前だけを返す。画面で隠すだけでは、応答を見れば分かってしまう
      def entry_json(node, readable)
        {
          id: node.id,
          kind: node.kind,
          name: node.name,
          readable: readable,
          owner: (node.creator&.display_name if readable),
          updated_at: (node.updated_at if readable),
          byte_size: (node.byte_size if readable && node.file?),
        }
      end
    end
  end
end
