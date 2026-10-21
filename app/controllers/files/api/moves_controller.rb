module Files
  module Api
    class MovesController < BaseController
      # 移動元の親フォルダと移動先の、両方の編集権限が要る（doc/files.md の「移動」）
      def create
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
        render json: { errors: [t("files.moves.conflict")] }, status: :unprocessable_content
      end
    end
  end
end
