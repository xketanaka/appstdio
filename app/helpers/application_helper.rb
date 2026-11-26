module ApplicationHelper
  include FormatUtils

  # 画面に出すシステム名。組織設定のタイトルラベルが無ければ（テナントに入る前も）プラットフォーム名
  def system_name(setting)
    setting&.title_label || Settings.platform_name
  end

  # アバターの画像の URL。未設定なら nil。一覧では includes(:avatar_attachment) で読んでおくこと
  def avatar_src(tenant_user)
    blob_id = tenant_user&.avatar_attachment&.blob_id
    avatar_path(tenant_user, blob_id) if blob_id
  end
end
