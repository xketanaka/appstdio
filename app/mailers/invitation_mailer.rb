class InvitationMailer < ApplicationMailer
  helper FormatUtils

  # 利用者の追加・再送で送る招待のメール（TenantUser#send_invitation!）
  def invitation(to:, tenant_name:, inviter_name:, token:, expires_at:)
    @tenant_name = tenant_name
    @inviter_name = inviter_name
    @url = invitation_url(token)
    @expires_at = expires_at
    mail(to:, subject: t(".subject", tenant: tenant_name))
  end
end
