module ApplicationHelper
  include FormatUtils

  # ブラウザのタイトルの、画面ごとに変わらない部分
  def title_prefix(setting)
    [Settings.system_title, setting&.title_label].compact.join(" | ")
  end

  # アバターの画像の URL。未設定なら nil。一覧では includes(:avatar_attachment) で読んでおくこと
  def avatar_src(tenant_user)
    blob_id = tenant_user&.avatar_attachment&.blob_id
    avatar_path(tenant_user, blob_id) if blob_id
  end
end
