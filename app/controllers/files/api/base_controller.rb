module Files
  module Api
    class BaseController < Files::BaseController
      class Forbidden < StandardError; end

      rescue_from(ActiveRecord::RecordNotFound) { head :not_found }
      rescue_from(Forbidden) { head :forbidden }

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

      # 1ファイルの大きさの上限と、容量の残りを確かめる。アップロード（新しいファイル・新しい版）の1段目で使う
      def upload_size_errors(byte_size)
        max = Settings.files.max_upload_bytes
        errors = []
        errors << t("files.nodes.too_large", max: helpers.number_to_human_size(max)) if byte_size > max
        errors << t("files.nodes.storage_full") if byte_size > current_tenant.files_setting.remaining_bytes
        errors
      end

      # ダイレクトアップロードの1段目の応答。blob を作り、ブラウザが中身を送る先を返す。
      # 形は @rails/activestorage の DirectUpload が読む形（Active Storage 標準の受け口と同じ）
      def render_direct_upload(blob_params)
        blob = ActiveStorage::Blob.create_before_direct_upload!(
          **blob_params.to_h.symbolize_keys, metadata: { uploaded_by: current_tenant_user.id },
        )
        render json: {
          signed_id: blob.signed_id,
          direct_upload: { url: blob.service_url_for_direct_upload, headers: blob.service_headers_for_direct_upload },
        }
      end

      # ダイレクトアップロードの2段目で受け取る blob。signed_id の署名は「サーバが発行した blob か」しか
      # 保証せず、誰に発行したかには結び付かない。1段目で書いた上げた人と一致し、まだどこにも付いて
      # おらず（ロゴなど、使用中の blob の流用を防ぐ）、中身が届いているものだけを受け付ける
      def uploaded_blob!(signed_id)
        blob = ActiveStorage::Blob.find_signed!(signed_id)
        if blob.metadata["uploaded_by"] != current_tenant_user.id || blob.attachments.exists? || !blob.service.exist?(blob.key)
          raise ActiveRecord::RecordNotFound
        end

        blob
      end

      # 中に作るフォルダ。閲覧できなければ 404、閲覧できても編集できなければ 403
      def editable_folder!(id)
        folder = Node.kept.folder.find(id)
        permission = access.effective_permission(folder)
        raise ActiveRecord::RecordNotFound unless permission.readable?
        raise Forbidden unless permission.editable?

        folder
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
      def entry_json(node, permission)
        readable = permission.readable?
        {
          id: node.id,
          kind: node.kind,
          name: node.name,
          readable:,
          editable: permission.editable?,
          owner: (node.creator&.display_name if readable),
          updated_at: (node.updated_at if readable),
          byte_size: (node.byte_size if readable && node.file?),
        }
      end
    end
  end
end
