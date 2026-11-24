# メールの設定は config/settings.yml の環境ごとの値から入れる。Settings は app/models にあり、
# 起動の途中では読み込めないので to_prepare で入れる
Rails.application.config.to_prepare do
  ActionMailer::Base.default_url_options = { host: Settings.host_name, protocol: Settings.protocol }
  ActionMailer::Base.smtp_settings = Settings.smtp.to_h
  # 指定が無ければ環境の設定のまま（本番は SMTP、テストは test）
  ActionMailer::Base.delivery_method = Settings.mailer.delivery_method.to_sym if Settings.mailer.delivery_method
end
