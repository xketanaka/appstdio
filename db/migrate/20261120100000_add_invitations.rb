class AddInvitations < ActiveRecord::Migration[8.1]
  def change
    # 招待メールを送った日時。期限はこれと組織設定の日数で決め、再送すると古い URL は使えなくなる
    add_column :tenant_users, :invitation_sent_at, :datetime

    add_column :tenant_settings, :invitation_expiry_days, :integer, null: false, default: 3
    add_check_constraint :tenant_settings, "invitation_expiry_days BETWEEN 1 AND 30",
      name: "tenant_settings_invitation_expiry_days_check"
  end
end
