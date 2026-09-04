class ApplicationMailer < ActionMailer::Base
  default from: Settings.mailer.from_address
  layout "mailer"
end
