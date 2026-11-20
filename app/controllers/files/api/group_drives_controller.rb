module Files
  module Api
    # 部署のグループドライブを使うかの設定（doc/files.md の「グループドライブ」）。
    # 設定できるのは、グループ管理でそのグループを管理できる人（テナントの管理者と、グループ管理者の範囲）
    class GroupDrivesController < BaseController
      before_action :set_group, only: [:enable, :disable]

      def index
        scope = GroupScope.new(current_tenant_user)
        groups = Group.department.active.to_a.select { scope.include?(it) }
        enabled = Drive.group_drive.where(group_id: groups.map(&:id), disabled_at: nil).pluck(:group_id).to_set

        render json: {
          groups: Group.sort_by_name_path(groups).map do |group, path|
            { id: group.id, name: group.name, path:, enabled: enabled.include?(group.id) }
          end,
        }
      end

      def enable
        Drive.enable_for!(@group)
        head :no_content
      end

      # 中身をゴミ箱へ入れるか（trash）は、画面で必ず選んでもらう
      def disable
        Drive.group_drive.find_by!(group: @group, disabled_at: nil)
          .disable!(actor: current_tenant_user, trash: ActiveModel::Type::Boolean.new.cast(params[:trash]))
        head :no_content
      end

      private

      def set_group
        @group = Group.department.active.find(params[:id])
        raise ActiveRecord::RecordNotFound unless GroupScope.new(current_tenant_user).include?(@group)
      end
    end
  end
end
