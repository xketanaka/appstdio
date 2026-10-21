module Files
  module Api
    class NodesController < BaseController
      # 保存先（ディスク・S3）の URL を、このリクエストのホスト名で作るため
      include ActiveStorage::SetCurrent

      # 移動元の親フォルダと移動先の、両方の編集権限が要る（doc/files.md の「移動」）
      def move
        ids = Array(params[:node_ids]).map(&:to_i).uniq
        destination = Node.kept.folder.find(params[:destination_id])
        nodes = Node.kept.where(id: ids).includes(:parent).to_a
        raise ActiveRecord::RecordNotFound if nodes.size != ids.size || nodes.any?(&:root?)

        permissions = access.effective_permissions([destination, *nodes.map(&:parent)].uniq)
        raise ActiveRecord::RecordNotFound unless [destination, *nodes.map(&:parent)].all? { permissions[it].readable? }
        return head :forbidden unless [destination, *nodes.map(&:parent)].all? { permissions[it].editable? }

        Node.move!(nodes, to: destination, actor: current_tenant_user)
        head :no_content
      rescue Node::MoveError => e
        render json: { errors: e.messages }, status: :unprocessable_content
      rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotUnique
        # 同じ名前のものが同時に移動先へ作られ、事前の確かめをすり抜けたとき
        render json: { errors: [t("files.nodes.move_conflict")] }, status: :unprocessable_content
      end

      # ダイレクトアップロードの1段目。確かめてから blob を作り、ブラウザが中身を送る先を返す。
      # 応答の形は @rails/activestorage の DirectUpload が読む形（Active Storage 標準の受け口と同じ）
      def prepare_upload
        parent = editable_folder!(params[:parent_id])
        blob_params = params.expect(blob: [:filename, :byte_size, :checksum, :content_type])
        errors = upload_errors(parent, name: blob_params[:filename].to_s, byte_size: blob_params[:byte_size].to_i)
        return render json: { errors: }, status: :unprocessable_content if errors.any?

        blob = ActiveStorage::Blob.create_before_direct_upload!(**blob_params.to_h.symbolize_keys)
        render json: {
          signed_id: blob.signed_id,
          direct_upload: { url: blob.service_url_for_direct_upload, headers: blob.service_headers_for_direct_upload },
        }
      end

      # 2段目。中身が届いた blob をファイルとして登録する。1段目のあとに容量が埋まったり、
      # 同じ名前ができたりしうるので、ここでも確かめる。登録できなければ届いた中身は消す
      def upload
        parent = editable_folder!(params[:parent_id])
        blob = ActiveStorage::Blob.find_signed!(params[:signed_blob_id])
        raise ActiveRecord::RecordNotFound if blob.attachments.exists? || !blob.service.exist?(blob.key)

        file = Node.create_file!(parent:, blob:, creator: current_tenant_user)
        render json: { id: file.id, name: file.name }, status: :created
      rescue Node::StorageFullError
        blob.purge_later
        render json: { errors: [t("files.nodes.storage_full")] }, status: :unprocessable_content
      rescue ActiveRecord::RecordInvalid => e
        blob.purge_later
        render json: { errors: e.record.errors.full_messages }, status: :unprocessable_content
      rescue ActiveRecord::RecordNotUnique
        blob.purge_later
        render json: { errors: [t("files.nodes.name_conflict")] }, status: :unprocessable_content
      end

      # 閲覧できれば、5分だけ有効な保存先の URL へ転送する。Active Storage の公開ルートは
      # 権限を確かめないので使わない（architecture.md の「テナント分離」）
      def download
        file = Node.kept.file.find(params[:id])
        raise ActiveRecord::RecordNotFound unless access.effective_permission(file).readable?

        url = file.current_version.body.url(
          expires_in: 5.minutes, disposition: :attachment, filename: ActiveStorage::Filename.new(file.name),
        )
        redirect_to url, allow_other_host: true
      end

      private

      def upload_errors(parent, name:, byte_size:)
        max = Settings.files.max_upload_bytes
        errors = []
        errors << t("files.nodes.too_large", max: helpers.number_to_human_size(max)) if byte_size > max
        node = Node.new(tenant_id: parent.tenant_id, drive_id: parent.drive_id, parent:, kind: :file, name:)
        node.validate
        errors.concat(node.errors.full_messages_for(:name))
        errors << t("files.nodes.storage_full") if byte_size > current_tenant.files_setting.remaining_bytes
        errors
      end
    end
  end
end
