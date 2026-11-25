class PasswordResetMailer < ApplicationMailer
  helper FormatUtils

  # パスワードを忘れたときに、新しいパスワードを決める URL を送る（User#send_password_reset）
  def reset(to:, token:, expires_at:)
    @url = edit_password_reset_url(token)
    @expires_at = expires_at
    mail(to:, subject: t(".subject", system: Settings.system_title))
  end
end
