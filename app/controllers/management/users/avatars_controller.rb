module Management
  module Users
    # 管理者は、不適切な画像を外せるよう、削除だけできる（差し替えは本人だけ）
    class AvatarsController < BaseController
      def destroy
        tenant_user = TenantUser.not_deleted.find(params[:user_id])
        tenant_user.avatar.purge
        redirect_to edit_management_user_path(tenant_user), notice: t(".done")
      end
    end
  end
end
