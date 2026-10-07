module Files
  class Access
    # 相関サブクエリ。外側のクエリの files_nodes の行ごとに評価される
    NEAREST_SQL = <<~SQL.squish
      SELECT DISTINCT ON (p.group_id, p.tenant_user_id) p.role
      FROM files_permissions p
      WHERE p.node_id = ANY(files_nodes.ancestor_ids || files_nodes.id)
        AND (p.tenant_user_id = :tenant_user_id OR p.group_id IN (:group_ids))
      ORDER BY p.group_id, p.tenant_user_id,
        array_position(files_nodes.ancestor_ids || files_nodes.id, p.node_id) DESC
    SQL

    # privileged: 特権モード中か。管理者・オーナーでなければ true を渡しても効かない
    def initialize(tenant_user, privileged: false)
      @tenant_user = tenant_user
      @privileged = privileged && tenant_user.admin_or_owner?
    end

    # 1ノードの権限。名前の変更・削除・ダウンロードなど、操作の可否を決めるときに使う
    def effective_permission(node)
      effective_permissions([node])[node]
    end

    # 複数ノードの権限。フォルダを開いたときの子の一覧のノードの判定等で使う
    def effective_permissions(nodes)
      ids = nodes.map(&:id)
      return EffectivePermission::Collection.new(ids.index_with("manager")) if @privileged

      ranked = EffectivePermission::RANKED_ROLES
      ranks = ranked.map { |role| "'#{role}'" }.join(",")
      roles = Node.where(id: ids)
        .joins(ActiveRecord::Base.sanitize_sql(["CROSS JOIN LATERAL (#{NEAREST_SQL}) nearest", subjects]))
        .where("nearest.role <> 'none'")
        .group(:id)
        .pluck(:id, Arel.sql("max(array_position(ARRAY[#{ranks}]::varchar[], nearest.role))"))
        .to_h { |id, rank| [id, ranked[rank - 1]] }
      EffectivePermission::Collection.new(roles)
    end

    # 閲覧できるノードに絞ったスコープ。DB での検索など、ページングや他の条件と組み合わせるときに使う
    def readable(scope)
      return scope if @privileged

      scope.where("EXISTS (SELECT 1 FROM (#{NEAREST_SQL}) nearest WHERE nearest.role <> 'none')", subjects)
    end

    # 「共有されたアイテム」の画面に並べるノード。
    # 特権で判定すると親が常に見えるため、付与された権限だけで判定する
    def shared_items
      granted = Permission.where.not(role: "none")
        .where("tenant_user_id = :tenant_user_id OR group_id IN (:group_ids)", subjects)
      candidates = Node.kept.where(id: granted.select(:node_id)).where.not(parent_id: nil).includes(:parent).to_a
      parents = Access.new(@tenant_user, privileged: false).effective_permissions(candidates.map(&:parent))

      candidates.reject { |node| parents[node.parent].readable? }
    end

    # ゴミ箱の画面に並べるノード（削除操作の起点のうち、親フォルダの編集者であるもの）
    def trash
      roots = Node.trash_roots.includes(:parent).to_a
      parents = effective_permissions(roots.map(&:parent))

      roots.select { |node| parents[node.parent].editable? }
    end

    private

    def subjects
      @subjects ||= begin
        memberships = GroupMember.where(tenant_user_id: @tenant_user.id).select(:group_id).to_sql
        belonging = Group.connection.select_values(<<~SQL.squish)
          WITH RECURSIVE belonging(id) AS (
            #{memberships}
            UNION
            SELECT groups.parent_id FROM groups JOIN belonging ON groups.id = belonging.id
            WHERE groups.parent_id IS NOT NULL
          )
          SELECT id FROM belonging
        SQL
        everyone = Group.everyone.where(tenant_id: @tenant_user.tenant_id).ids
        { tenant_user_id: @tenant_user.id, group_ids: (belonging + everyone).presence || [nil] }
      end
    end
  end
end
