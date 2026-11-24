# メールの設定は config/settings.yml の環境ごとの値から入れる。Settings は app/models にあり、
# 起動の途中では読み込めないので to_prepare で入れる
Rails.application.config.to_prepare do
  # app_url が空なら空にする。production.rb の既定（example.com）のまま誤った URL を送らず、
  # URL を作るところで Missing host to link to! で失敗させる
  url = Settings.app_url.presence && URI(Settings.app_url)
  ActionMailer::Base.default_url_options =
    url ? { protocol: url.scheme, host: url.host, port: (url.port unless url.port == url.default_port) }.compact : {}
  ActionMailer::Base.smtp_settings = Settings.smtp.to_h
  # 指定が無ければ環境の設定のまま（本番は SMTP、テストは test）
  ActionMailer::Base.delivery_method = Settings.mailer.delivery_method.to_sym if Settings.mailer.delivery_method
end
