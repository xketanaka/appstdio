module Files
  module Api
    # ファイルの版。一覧とダウンロードは閲覧できれば、版を足す・ラベルを変える・最新に戻すは
    # そのファイル自身の編集権限が要る（仕様の表の「編集者: ファイルの内容更新」）
    class VersionsController < BaseController
      # 保存先（ディスク・S3）の URL を、このリクエストのホスト名で作るため
      include ActiveStorage::SetCurrent

      before_action :set_file
      before_action :editable_required, except: [:index, :download]

      def index
        versions = @file.versions.includes(:creator).order(number: :desc)
        render json: {
          can_edit: @permission.editable?,
          versions: versions.map do |version|
            {
              id: version.id,
              number: version.number,
              label: version.label,
              byte_size: version.byte_size,
              creator: version.creator&.display_name,
              created_at: version.created_at,
              current: version.id == @file.current_version_id,
              purged: version.purged_at.present?,
            }
          end,
        }
      end

      # 新しい版を上げる1段目。上げたファイルの名前は使わない（ファイルの名前は変わらない）
      def prepare_upload
        blob_params = params.expect(blob: [:filename, :byte_size, :checksum, :content_type])
        errors = upload_size_errors(blob_params[:byte_size].to_i)
        return render json: { errors: }, status: :unprocessable_content if errors.any?

        render_direct_upload(blob_params)
      end

      # 2段目。中身の届いた blob を新しい版として足す
      def create
        blob = ActiveStorage::Blob.find_signed!(params[:signed_blob_id])
        raise ActiveRecord::RecordNotFound if blob.attachments.exists? || !blob.service.exist?(blob.key)

        version = @file.add_version!(blob:, creator: current_tenant_user)
        render json: { id: @file.id, name: @file.name, version: version.number }, status: :created
      rescue Node::StorageFullError
        blob.purge_later
        render json: { errors: [t("files.nodes.storage_full")] }, status: :unprocessable_content
      end

      def update
        version = @file.versions.find(params[:id])
        version.update!(label: params[:label].to_s.strip.presence)
        head :no_content
      rescue ActiveRecord::RecordInvalid => e
        render json: { errors: e.record.errors.full_messages }, status: :unprocessable_content
      end

      def download
        version = @file.versions.kept.find(params[:id])
        url = version.body.url(
          expires_in: 5.minutes, disposition: :attachment, filename: ActiveStorage::Filename.new(@file.name),
        )
        redirect_to url, allow_other_host: true
      end

      # 古い版の中身を写して、新しい番号の版を作る。古い版を消したり、番号を巻き戻したりはしない
      def restore
        version = @file.versions.kept.find(params[:id])
        restored = @file.add_version!(blob: version.body.blob, creator: current_tenant_user, restored_from: version.number)
        render json: { version: restored.number }, status: :created
      rescue Node::StorageFullError
        render json: { errors: [t("files.nodes.storage_full")] }, status: :unprocessable_content
      end

      private

      def set_file
        @file = Node.kept.file.find(params[:node_id])
        @permission = access.effective_permission(@file)
        raise ActiveRecord::RecordNotFound unless @permission.readable?
      end

      def editable_required
        raise Forbidden unless @permission.editable?
      end
    end
  end
end
