class OperatorMailer < ApplicationMailer
  helper FormatUtils

  # 運営者がパスワードを忘れたときに、新しいパスワードを決める URL を送る（Operator#send_password_reset）。
  # URL は運営者画面のプロセスで組み立てて渡す
  def password_reset(to:, url:, expires_at:)
    @console = t("operator_mailer.console", platform: Settings.platform_name)
    @url = url
    @expires_at = expires_at
    mail(to:, subject: t(".subject", console: @console))
  end
end
