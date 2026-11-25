class InvitationMailer < ApplicationMailer
  helper FormatUtils

  # 利用者の追加・再送で送る招待のメール（TenantUser#send_invitation!）。token があればパスワードを決める
  # URL（新しいアカウント）を、無ければログインの URL（組織の選択から参加する）を書く
  def invitation(to:, tenant_name:, title_label:, inviter_name:, token:, expires_at:)
    @tenant_name = tenant_name
    @target = if title_label
      t(".target_with_system", platform: Settings.platform_name, system: title_label, tenant: tenant_name)
    else
      t(".target", platform: Settings.platform_name, tenant: tenant_name)
    end
    @inviter_name = inviter_name
    @new_account = token.present?
    @url = @new_account ? invitation_url(token) : login_url
    @expires_at = expires_at
    mail(to:, subject: t(".subject", target: @target))
  end
end
