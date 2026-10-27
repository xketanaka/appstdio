module Files
  module Api
    # 共有設定の画面。見るのも変えるのも、そのもの自身の管理者の権限が要る（仕様の表の
    # 「管理者: 共有設定の変更」）。変更は画面を開いたときからの差分だけを受け取り、まとめて反映する
    class PermissionsController < BaseController
      before_action :set_node

      def show
        own = @node.permissions.includes(:group, :tenant_user).index_by(&:subject_key)
        inherited = Permission.nearest_on_path(@node.ancestor_ids).values.reject(&:role_none?)
        sources = Node.where(id: inherited.map(&:node_id)).includes(drive: :owner).index_by(&:id)

        render json: {
          inherited: inherited.sort_by { subject_sort_key(it) }.map do |setting|
            source = sources.fetch(setting.node_id)
            {
              subject: subject_json(setting),
              role: setting.role,
              # 共有されたフォルダの管理者には、上位のフォルダが見えないことがある。名前は見える場合だけ返す
              from: access.effective_permission(source).readable? ? { id: source.id, label: node_label(source) } : nil,
              cancelled: own[setting.subject_key]&.role_none? || false,
            }
          end,
          own: own.values.reject(&:role_none?).sort_by { subject_sort_key(it) }
            .map { { subject: subject_json(it), role: it.role } },
        }
      end

      def update
        changes = params.expect(changes: [[:subject_type, :subject_id, :role]]).map do |change|
          role = change[:role].presence
          raise ActiveRecord::RecordNotFound unless role.nil? || Permission::ROLES.include?(role)

          group = change[:subject_type] == "group"
          subject = group ? Group.find(change[:subject_id]) : TenantUser.find(change[:subject_id])
          key = group ? { group_id: subject.id, tenant_user_id: nil } : { group_id: nil, tenant_user_id: subject.id }
          # 新しく加える相手は、選べる候補（share_candidates）と同じ条件に限る
          addable = group ? !subject.suspended? : subject.active? || subject.invited?
          if role && !addable && !@node.permissions.exists?(**key)
            name = group ? subject.name : subject.display_name
            return render json: { errors: [t("files.permissions.not_addable", name:)] }, status: :unprocessable_content
          end

          { **key, role: }
        end

        Permission.apply_changes!(@node, changes, actor: current_tenant_user)
        head :no_content
      rescue Permission::NoManagerError
        render json: { errors: [t("files.permissions.no_manager")] }, status: :unprocessable_content
      end

      private

      def set_node
        @node = Node.kept.find(params[:node_id])
        permission = access.effective_permission(@node)
        raise ActiveRecord::RecordNotFound unless permission.readable?
        raise Forbidden unless permission.manageable?
      end

      # 「全員」を先頭に、グループ、人の順
      def subject_sort_key(setting)
        if setting.group&.everyone? then [0, ""]
        elsif setting.group then [1, setting.group.name]
        else [2, setting.tenant_user.display_name]
        end
      end

      def subject_json(setting)
        if setting.group
          { type: "group", id: setting.group_id, name: setting.group.name, everyone: setting.group.everyone?,
            suspended: setting.group.suspended? }
        else
          { type: "tenant_user", id: setting.tenant_user_id, name: setting.tenant_user.display_name, everyone: false,
            suspended: setting.tenant_user.suspended? }
        end
      end
    end
  end
end
