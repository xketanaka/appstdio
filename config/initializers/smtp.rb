Rails.application.config.to_prepare do
  Rails.application.config.action_mailer.default_url_options = {
    host: Settings.host_name,
    protocol: Settings.protocol,
  }
  Rails.application.config.action_mailer.smtp_settings = Settings.smtp.to_h
end
