module ApplicationHelper
  include FormatUtils

  # ブラウザのタイトルの、画面ごとに変わらない部分
  def title_prefix(setting)
    [Settings.system_title, setting&.title_label].compact.join(" | ")
  end
end
