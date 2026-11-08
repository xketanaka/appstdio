module Files
  module Api
    # 名前の部分一致で、閲覧できるものを探す（doc/files.md の「検索」）。in は検索を始めた場所
    # （組織共有ドライブ・マイドライブ・共有されたアイテム・ゴミ箱・フォルダの id）で、その中から探す。
    # all を付けると、ゴミ箱を除くすべての場所から探す
    class SearchesController < BaseController
      LIMIT = 100

      def show
        origin = origin!(params[:in])
        everywhere = params[:all] == "1" || origin[:scope].nil?
        query = params[:q].to_s.strip
        trash = origin[:in] == "trash" && !everywhere

        found =
          if query.empty?
            []
          elsif trash
            access.trash.select { it.name.downcase.include?(query.downcase) }.sort_by(&:deleted_at).reverse
          else
            scope = (everywhere ? Node.kept : origin[:scope]).where.not(parent_id: nil)
              .where("files_nodes.name ILIKE ?", "%#{Node.sanitize_sql_like(query)}%")
            access.readable(scope).includes(:creator).order(updated_at: :desc).limit(LIMIT + 1).to_a
          end
        entries = found.first(LIMIT)
        ActiveRecord::Associations::Preloader.new(records: entries, associations: :deleted_by).call if trash
        permissions = access.effective_permissions(entries)

        # 場所は、フォルダの画面のパンくずと同じく、閲覧できる祖先だけを根元の側から並べる
        ancestors = Node.where(id: entries.flat_map(&:ancestor_ids)).includes(drive: :owner).index_by(&:id)
        ancestor_permissions = access.effective_permissions(ancestors.values)

        render json: {
          origin: origin.slice(:in, :label),
          everywhere:,
          trash:,
          truncated: found.size > LIMIT,
          entries: entries.map do |node|
            path = node.ancestor_ids.map { ancestors[it] }
            visible = path.reverse.take_while { ancestor_permissions[it].readable? }.reverse
            (trash ? trash_entry_json(node) : entry_json(node, permissions[node])).merge(
              location: visible.map { { id: it.id, label: node_label(it) } },
              via_shared: visible.size < path.size,
            )
          end,
        }
      end

      private

      # 検索を始めた場所と、その中のものを選ぶスコープ。場所が無ければ scope は nil（すべての場所）。
      # フォルダを閲覧できなければ 404
      def origin!(key)
        case key
        when "shared_drive"
          root = Drive.shared_root(current_tenant)
          { in: key, label: t("files.drives.shared"), scope: Node.kept.where(drive_id: root.drive_id) }
        when "my_drive"
          root = Drive.personal_root(current_tenant_user)
          { in: key, label: t("files.drives.mine"), scope: Node.kept.where(drive_id: root.drive_id) }
        when "shared_with_me"
          ids = access.shared_items.map(&:id).presence || [0]
          {
            in: key, label: t("files.sections.shared_with_me"),
            scope: Node.kept.where("(files_nodes.ancestor_ids || files_nodes.id) && ARRAY[?]::bigint[]", ids),
          }
        when "trash"
          { in: key, label: t("files.sections.trash"), scope: Node.none }
        when /\A\d+\z/
          folder = Node.kept.folder.find(key)
          raise ActiveRecord::RecordNotFound unless access.effective_permission(folder).readable?

          { in: key, label: node_label(folder), scope: Node.kept.where("? = ANY(files_nodes.ancestor_ids)", folder.id) }
        else
          { in: nil, label: nil, scope: nil }
        end
      end
    end
  end
end
