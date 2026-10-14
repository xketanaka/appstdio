module Management
  class TenantSettingsController < BaseController
    before_action :set_settings

    def show
    end

    def edit
    end

    def update
      attributes = params.expect(tenant_setting: [:title_label, :title_color, :logo])
      attributes[:title_color] = nil if params[:use_default_color] == "1"
      attributes[:logo] = nil if params[:remove_logo] == "1"
      @setting.assign_attributes(attributes)
      @files_setting.enabled = params[:files_enabled] == "1"

      saved = TenantSetting.transaction do
        (@setting.save && @files_setting.save) || raise(ActiveRecord::Rollback)
      end

      if saved
        redirect_to management_tenant_setting_path, notice: t("messages.saved")
      else
        render :edit, status: :unprocessable_entity
      end
    end

    private

    def set_settings
      # current_tenant.setting はヘッダーが使う。同じオブジェクトだと、検証に
      # 失敗して編集画面を出し直したときに保存前の値がヘッダーに出る
      @setting = TenantSetting.find_by!(tenant: current_tenant)
      @files_setting = Files::Setting.find_by!(tenant: current_tenant)
    end
  end
end
