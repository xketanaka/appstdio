module Management
  # テナント管理者（owner / admin）向けの画面。システム管理画面（/admin）とは別物
  class BaseController < ApplicationController
    layout "management"

    before_action :tenant_manager_required

    def tenant_manager_required
      return if current_tenant_user.manager?

      # 権限の無い利用者には画面の存在自体を見せない
      render file: Rails.root.join("public/404.html"), status: :not_found, layout: false
    end
  end
end
