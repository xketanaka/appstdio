module Files
  # ある利用者があるノードに対して、継承と打ち消しを計算した結果として持つ権限。
  # 設定として保存されている1行は Files::Permission
  class EffectivePermission
    RANKED_ROLES = %w[viewer editor manager].freeze

    # "viewer" / "editor" / "manager"。権限が無ければ nil
    attr_reader :role

    def initialize(role)
      @role = role
    end

    def readable?
      RANKED_ROLES.include?(role)
    end

    def editable?
      %w[editor manager].include?(role)
    end

    def manageable?
      role == "manager"
    end

    # 複数ノード分の計算結果。権限の無いノードにも「権限なし」を返す
    class Collection
      def initialize(roles_by_node_id)
        @roles_by_node_id = roles_by_node_id
      end

      def [](node)
        EffectivePermission.new(@roles_by_node_id[node.id])
      end
    end
  end
end
