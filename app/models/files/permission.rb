module Files
  class Permission < ApplicationRecord
    # none は打ち消し。継承してきた権限をこのノードで無効にする。
    # 他の主体からの付与までは打ち消さない（拒否ではない）
    ROLES = %w[none viewer editor manager].freeze

    # none は ActiveRecord の none スコープと衝突するため接頭辞を付ける
    enum :role, ROLES.index_by(&:itself), prefix: :role, validate: true

    belongs_to :tenant
    belongs_to :node, class_name: "Files::Node"
    belongs_to :group, optional: true
    belongs_to :tenant_user, optional: true

    validate :exactly_one_subject
    validates :group_id, uniqueness: { scope: :node_id }, if: :group_id?
    validates :tenant_user_id, uniqueness: { scope: :node_id }, if: :tenant_user_id?

    # 管理者がいなくなる変更を断るときの例外（doc/files.md の「共有設定」）
    class NoManagerError < StandardError; end

    def subject
      group || tenant_user
    end

    def subject_key
      [group_id, tenant_user_id]
    end

    # 経路（祖先から自分の順の node の id）の設定のうち、主体ごとに最も近いもの。
    # 打ち消し（none）も含む。{ [group_id, tenant_user_id] => Permission }
    def self.nearest_on_path(path_ids)
      where(node_id: path_ids).includes(:group, :tenant_user).to_a
        .group_by(&:subject_key)
        .transform_values { |settings| settings.max_by { path_ids.index(it.node_id) } }
    end

    # そのノードに、管理者の権限が実在する人まで届いているか。有効・招待中の人、そういうメンバーの
    # いる有効なグループ（下位のメンバーを含む）、「全員」のどれかが管理者なら届いている。
    # 停止中のグループの所属を数えないのは Files::Access と同じ
    def self.manager_reachable?(node)
      path = Node.where(id: node.id).pick(:ancestor_ids) + [node.id]
      managers = nearest_on_path(path).values.select(&:role_manager?)
      return true if managers.any? { it.group&.everyone? }
      return true if TenantUser.where(id: managers.filter_map(&:tenant_user_id), status: [:active, :invited]).exists?

      groups = Group.active.where(id: managers.filter_map(&:group_id)).ids
      return false if groups.empty?

      GroupMember.where(group_id: Group.active.where(id: groups + Group.descendant_ids_of(groups)).select(:id))
        .joins(:tenant_user).merge(TenantUser.where(status: [:active, :invited])).exists?
    end

    # 共有設定の画面で編集した差分を、1つのトランザクションで反映する。changes は
    # [{ group_id:, tenant_user_id:, role: }]。role が nil ならこのノードの設定を消す（継承に戻す）。
    # 変更の前は管理者がいたのに、いなくなるなら NoManagerError で何も残さない
    def self.apply_changes!(node, changes, actor:)
      had_manager = manager_reachable?(node)
      transaction do
        changes.each do |change|
          subject = change.slice(:group_id, :tenant_user_id)
          current = find_by(node:, **subject)
          if change[:role].nil?
            current&.destroy!
          elsif current
            current.update!(role: change[:role])
          else
            create!(tenant_id: node.tenant_id, node:, role: change[:role], **subject)
          end
        end
        raise NoManagerError if had_manager && !manager_reachable?(node)

        Activity.create!(tenant_id: node.tenant_id, node:, actor:, action: :shared, detail: { changes: })
      end
    end

    private

    def exactly_one_subject
      return if group_id.present? ^ tenant_user_id.present?

      errors.add(:base, :invalid)
    end
  end
end
