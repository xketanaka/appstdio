# smtp.rb は setting_config.rb より後に読み込まれるので、
# Settings 経由で設定ファイルの値を参照する
Rails.application.config.action_mailer.default_url_options = {
  host: Settings.host_name,
  protocol: Settings.protocol,
}
Rails.application.config.action_mailer.smtp_settings = Settings.smtp.to_h
