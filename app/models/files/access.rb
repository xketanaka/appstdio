module Files
  class Access
    RANKED_ROLES = %w[viewer editor manager].freeze

    # 相関サブクエリ。外側のクエリの files_nodes の行ごとに評価される
    NEAREST_SQL = <<~SQL.squish
      SELECT DISTINCT ON (p.group_id, p.tenant_user_id) p.role
      FROM files_permissions p
      WHERE p.node_id = ANY(files_nodes.ancestor_ids || files_nodes.id)
        AND (p.tenant_user_id = :tenant_user_id OR p.group_id IN (:group_ids))
      ORDER BY p.group_id, p.tenant_user_id,
        array_position(files_nodes.ancestor_ids || files_nodes.id, p.node_id) DESC
    SQL

    def self.at_least?(role, required)
      role.present? && RANKED_ROLES.index(role) >= RANKED_ROLES.index(required.to_s)
    end

    def initialize(tenant_user, privileged: true)
      @tenant_user = tenant_user
      @privileged = privileged && tenant_user.manager?
    end

    def role(node)
      roles([node])[node.id]
    end

    def roles(nodes)
      ids = nodes.map(&:id)
      return ids.index_with("manager") if @privileged

      ranks = RANKED_ROLES.map { |role| "'#{role}'" }.join(",")
      Node.where(id: ids)
        .joins(ActiveRecord::Base.sanitize_sql(["CROSS JOIN LATERAL (#{NEAREST_SQL}) nearest", subjects]))
        .where("nearest.role <> 'none'")
        .group(:id)
        .pluck(:id, Arel.sql("max(array_position(ARRAY[#{ranks}]::varchar[], nearest.role))"))
        .to_h { |id, rank| [id, RANKED_ROLES[rank - 1]] }
    end

    def readable(scope)
      return scope if @privileged

      scope.where("EXISTS (SELECT 1 FROM (#{NEAREST_SQL}) nearest WHERE nearest.role <> 'none')", subjects)
    end

    # 特権で判定すると親が常に見えるため、付与された権限だけで判定する
    def shared_items
      granted = Permission.where.not(role: "none")
        .where("tenant_user_id = :tenant_user_id OR group_id IN (:group_ids)", subjects)
      candidates = Node.kept.where(id: granted.select(:node_id)).where.not(parent_id: nil).to_a
      parents = Node.where(id: candidates.map(&:parent_id)).to_a
      visible = Access.new(@tenant_user, privileged: false).roles(parents)

      candidates.reject { |node| visible.key?(node.parent_id) }
    end

    def trash
      roots = Node.trash_roots.includes(:parent).to_a
      parent_roles = roles(roots.map(&:parent))

      roots.select { |node| Access.at_least?(parent_roles[node.parent_id], :editor) }
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
