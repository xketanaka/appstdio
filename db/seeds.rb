# This file should ensure the existence of records required to run the application in every environment (production,
# development, test). The code here should be idempotent so that it can be executed at any point in every environment.
# The data can then be loaded with the bin/rails db:seed command (or created alongside the database with db:setup).

if Rails.env.local?
  password = "password1234"
  user = User.find_or_initialize_by(email: "admin@example.com")
  user.password = password if user.new_record?
  user.save!

  # テナント選択画面を確認できるように2件用意する
  ["サンプル株式会社", "テスト工業"].each_with_index do |name, index|
    tenant = Tenant.find_or_create_by!(name: name)

    # tenant_users は RLS の対象なので、テナントのコンテキストを設定してから操作する
    TenantContext.switch(tenant: tenant) do
      membership = TenantUser.find_or_initialize_by(tenant_id: tenant.id, user_id: user.id)
      membership.display_name = "管理者"
      membership.role = index.zero? ? :owner : :member
      membership.status = :active
      membership.save!
    end
  end

  puts "ログイン: #{user.email} / #{password}"
end
