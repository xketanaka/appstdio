module Files
  class Access
    # 相関サブクエリ。外側のクエリの files_nodes の行ごとに評価される。
    # グループ管理者は、自分が管理するグループのドライブのルートに、本人=管理者の行があるものとして数える。
    # 同じ位置に本人の行が実際にもあれば、強い方を採る
    NEAREST_SQL = <<~SQL.squish
      SELECT DISTINCT ON (p.group_id, p.tenant_user_id) p.role
      FROM (
        SELECT node_id, group_id, tenant_user_id, role FROM files_permissions
        UNION ALL
        SELECT unnest(ARRAY[:led_root_ids]::bigint[]), NULL, :tenant_user_id, 'manager'
      ) p
      WHERE p.node_id = ANY(files_nodes.ancestor_ids || files_nodes.id)
        AND (p.tenant_user_id = :tenant_user_id OR p.group_id IN (:group_ids))
      ORDER BY p.group_id, p.tenant_user_id,
        array_position(files_nodes.ancestor_ids || files_nodes.id, p.node_id) DESC,
        array_position(ARRAY['viewer', 'editor', 'manager']::varchar[], p.role) DESC NULLS LAST
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
    # 使わないにしたグループドライブなどの中は、特権モードでも権限なしにする
    def effective_permissions(nodes)
      visible = Node.where(id: nodes.map(&:id)).where.not(drive_id: Drive.unavailable.select(:id))
      return EffectivePermission::Collection.new(visible.ids.index_with("manager")) if @privileged

      ranked = EffectivePermission::RANKED_ROLES
      ranks = ranked.map { |role| "'#{role}'" }.join(",")
      roles = visible
        .joins(ActiveRecord::Base.sanitize_sql(["CROSS JOIN LATERAL (#{NEAREST_SQL}) nearest", subjects]))
        .where("nearest.role <> 'none'")
        .group(:id)
        .pluck(:id, Arel.sql("max(array_position(ARRAY[#{ranks}]::varchar[], nearest.role))"))
        .to_h { |id, rank| [id, ranked[rank - 1]] }
      EffectivePermission::Collection.new(roles)
    end

    # 閲覧できるノードに絞ったスコープ。DB での検索など、ページングや他の条件と組み合わせるときに使う
    def readable(scope)
      scope = scope.where.not(drive_id: Drive.unavailable.select(:id))
      return scope if @privileged

      scope.where("EXISTS (SELECT 1 FROM (#{NEAREST_SQL}) nearest WHERE nearest.role <> 'none')", subjects)
    end

    # 「共有されたアイテム」の画面に並べるノード。
    # 特権で判定すると親が常に見えるため、付与された権限だけで判定する
    def shared_items
      granted = Permission.where.not(role: "none")
        .where("tenant_user_id = :tenant_user_id OR group_id IN (:group_ids)", subjects)
      candidates = Node.kept.where(id: granted.select(:node_id)).where.not(parent_id: nil)
        .where.not(drive_id: Drive.unavailable.select(:id)).includes(:parent).to_a
      parents = Access.new(@tenant_user, privileged: false).effective_permissions(candidates.map(&:parent))

      candidates.reject { |node| parents[node.parent].readable? }
    end

    # ゴミ箱の画面に並べるノード（削除操作の起点のうち、親フォルダの編集者であるもの）
    def trash
      roots = Node.trash_roots.includes(:parent).to_a
      parents = effective_permissions(roots.map(&:parent))

      roots.select { |node| parents[node.parent].editable? }
    end

    # 所属するグループ（上位と「全員」を含む）。停止中のグループは含まない
    def belonging_group_ids
      subjects[:group_ids].compact
    end

    private

    def subjects
      @subjects ||= begin
        # 利用停止中のグループの所属は数えない。停止中の下位はすべて停止中なので、有効なグループから
        # 上へたどった先も有効なグループだけになる
        memberships = GroupMember.where(tenant_user_id: @tenant_user.id, group_id: Group.active.select(:id))
          .select(:group_id).to_sql
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
        led_root_ids = Node.where(parent_id: nil, drive_id: Drive.group_drive
          .where(group_id: GroupMember.leader.where(tenant_user_id: @tenant_user.id).select(:group_id)).select(:id)).ids
        {
          tenant_user_id: @tenant_user.id,
          group_ids: (belonging + everyone).presence || [nil],
          led_root_ids: led_root_ids.presence || [nil],
        }
      end
    end
  end
end
