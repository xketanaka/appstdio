module Files
  module Api
    # 操作履歴（doc/files.md の「操作履歴」）。フォルダなら配下すべての分も、新しい順に PER_PAGE 件ずつ返す。
    # 閲覧できるものの分だけを返し、続きは before に前回の最後の id を渡して読む
    class ActivitiesController < BaseController
      PER_PAGE = 50

      def index
        target = Node.kept.find(params[:node_id])
        raise ActiveRecord::RecordNotFound unless access.effective_permission(target).readable?

        nodes = access.readable(Node.where("files_nodes.id = :id OR :id = ANY(files_nodes.ancestor_ids)", id: target.id))
        scope = Activity.where(node_id: nodes.select(:id))
        scope = scope.where(id: ...params[:before].to_i) if params[:before].present?
        found = scope.includes(:actor, :node).order(id: :desc).limit(PER_PAGE + 1).to_a
        activities = found.first(PER_PAGE)

        # 場所（対象のフォルダより下の祖先）と移動元・移動先の名前は、閲覧できるものだけ出す
        folder_ids = activities.flat_map do |activity|
          [*activity.node.ancestor_ids, *activity.detail.values_at("from", "to").grep(Integer)]
        end
        folders = Node.where(id: folder_ids).includes(drive: :owner).index_by(&:id)
        permissions = access.effective_permissions(folders.values)
        label = ->(id) { folders[id] && permissions[folders[id]].readable? ? node_label(folders[id]) : nil }

        render json: {
          activities: activities.map do |activity|
            node = activity.node
            below = node.ancestor_ids.drop_while { it != target.id }.drop(1)
            detail = activity.detail
            {
              id: activity.id,
              action: activity.action,
              actor: activity.actor&.display_name,
              created_at: activity.created_at,
              node: { id: node.id, kind: node.kind, name: node.name },
              location: below.map { label.(it) },
              # 共有設定の変更の中身（だれに何を付けたか）は出さない
              detail:
                case activity.action
                when "updated" then detail.slice("version", "restored_from")
                when "renamed" then detail.slice("from", "to")
                when "moved" then { from: label.(detail["from"]), to: label.(detail["to"]) }
                else {}
                end,
            }
          end,
          next_before: (activities.last.id if found.size > PER_PAGE),
        }
      end
    end
  end
end
