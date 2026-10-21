module Files
  # ファイル画面は Vue のアプリ。どの URL を直接開いても同じ入れ物のページを返し、
  # 何を表示するかは Vue Router が URL から決める
  class AppController < BaseController
    def show
      @config = {
        messages: I18n.t("files_app"),
        title_prefix: helpers.title_prefix(current_tenant.setting),
        admin_or_owner: current_tenant_user.admin_or_owner?,
        privileged: privileged_mode?,
      }
    end
  end
end
