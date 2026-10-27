module Files
  module Api
    class NodesController < BaseController
      # 保存先（ディスク・S3）の URL を、このリクエストのホスト名で作るため
      include ActiveStorage::SetCurrent

      # 移動元の親フォルダと移動先の、両方の編集権限が要る（doc/files.md の「移動」）
      def move
        destination = Node.kept.folder.find(params[:destination_id])
        nodes = editable_children!(Node.kept, params[:node_ids], also: [destination])

        Node.move!(nodes, to: destination, actor: current_tenant_user)
        head :no_content
      rescue Node::OperationError => e
        render json: { errors: e.messages }, status: :unprocessable_content
      rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotUnique
        # 同じ名前のものが同時に移動先へ作られ、事前の確かめをすり抜けたとき
        render json: { errors: [t("files.nodes.move_conflict")] }, status: :unprocessable_content
      end

      def rename
        node = editable_children!(Node.kept, [params[:id]]).first
        node.rename!(params[:name], actor: current_tenant_user)
        head :no_content
      rescue ActiveRecord::RecordInvalid => e
        render json: { errors: e.record.errors.full_messages }, status: :unprocessable_content
      rescue ActiveRecord::RecordNotUnique
        render json: { errors: [t("files.nodes.name_conflict")] }, status: :unprocessable_content
      end

      def trash
        Node.trash!(editable_children!(Node.kept, params[:node_ids]), actor: current_tenant_user)
        head :no_content
      end

      # 戻せるのは、ゴミ箱に出ているもの（削除したときに選んだもの）だけ。その中にあったものは一緒に戻る
      def restore
        Node.restore!(editable_children!(Node.trash_roots, params[:node_ids]), actor: current_tenant_user)
        head :no_content
      rescue Node::OperationError => e
        render json: { errors: e.messages }, status: :unprocessable_content
      end

      # ダイレクトアップロードの1段目。確かめてから、ブラウザが中身を送る先を返す。
      # 同じ名前のファイルがあれば、新しいファイルではなくその新しい版にする（doc/files.md の「版」）。
      # そのときは、そのファイル自身の編集権限が要る
      def prepare_upload
        parent = editable_folder!(params[:parent_id])
        blob_params = params.expect(blob: [:filename, :byte_size, :checksum, :content_type])
        name = blob_params[:filename].to_s
        node = Node.new(tenant_id: parent.tenant_id, drive_id: parent.drive_id, parent:, kind: :file, name:)
        node.validate
        existing = parent.children.kept.find_by(name: name.strip)
        node.errors.delete(:name, :taken) if existing&.file?

        errors = upload_size_errors(blob_params[:byte_size].to_i) + node.errors.full_messages_for(:name)
        if existing&.file? && !access.effective_permission(existing).editable?
          errors << t("files.nodes.version_forbidden", name: existing.name)
        end
        return render json: { errors: }, status: :unprocessable_content if errors.any?

        render_direct_upload(blob_params)
      end

      # 2段目。中身が届いた blob をファイルとして登録する。1段目のあとに容量が埋まったり、
      # 同じ名前ができたりしうるので、ここでも確かめる。登録できなければ届いた中身は消す
      def upload
        parent = editable_folder!(params[:parent_id])
        blob = uploaded_blob!(params[:signed_blob_id])

        existing = parent.children.kept.file.find_by(name: blob.filename.to_s)
        if existing
          unless access.effective_permission(existing).editable?
            blob.purge_later
            raise Forbidden
          end
          version = existing.add_version!(blob:, creator: current_tenant_user)
          render json: { id: existing.id, name: existing.name, version: version.number }, status: :created
        else
          file = Node.create_file!(parent:, blob:, creator: current_tenant_user)
          render json: { id: file.id, name: file.name, version: nil }, status: :created
        end
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
      # 権限を確かめないので使わない（doc/database.md の「テナント分離」）
      def download
        file = Node.kept.file.find(params[:id])
        raise ActiveRecord::RecordNotFound unless access.effective_permission(file).readable?

        url = file.current_version.body.url(
          expires_in: 5.minutes, disposition: :attachment, filename: ActiveStorage::Filename.new(file.name),
        )
        redirect_to url, allow_other_host: true
      end

      private

      # 名前の変更・移動・削除・復元は、どれも親フォルダの編集権限が要る（doc/files.md）。
      # also には、移動先など、親と一緒に編集権限を確かめるフォルダを渡す
      def editable_children!(scope, ids, also: [])
        ids = Array(ids).map(&:to_i).uniq
        nodes = scope.where(id: ids).includes(:parent).to_a
        raise ActiveRecord::RecordNotFound if nodes.empty? || nodes.size != ids.size || nodes.any?(&:root?)

        folders = [*also, *nodes.map(&:parent)].uniq
        permissions = access.effective_permissions(folders)
        raise ActiveRecord::RecordNotFound unless folders.all? { permissions[it].readable? }
        raise Forbidden unless folders.all? { permissions[it].editable? }

        nodes
      end
    end
  end
end
