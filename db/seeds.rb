# This file should ensure the existence of records required to run the application in every environment (production,
# development, test). The code here should be idempotent so that it can be executed at any point in every environment.
# The data can then be loaded with the bin/rails db:seed command (or created alongside the database with db:setup).

if Rails.env.local?
  password = "password1234"

  def upsert_user(email, password)
    User.find_or_initialize_by(email: email).tap do |user|
      user.password = password if user.new_record?
      user.save!
    end
  end

  # tenant_users は RLS の対象なので、テナントのコンテキストを設定してから操作する
  def join(tenant, user, display_name, role)
    TenantContext.switch(tenant: tenant) do
      membership = TenantUser.find_or_initialize_by(tenant_id: tenant.id, user_id: user.id)
      membership.display_name = display_name
      membership.role = role
      membership.status = :active
      membership.save!
    end
  end

  sample = Tenant.find_or_create_by!(name: "サンプル株式会社")
  test = Tenant.find_or_create_by!(name: "テスト工業")

  # 所属が複数あるユーザ。ログイン後にテナント選択画面が出る
  admin = upsert_user("admin@example.com", password)
  join(sample, admin, "管理者", :owner)
  join(test, admin, "管理者", :member)

  # 所属が1件のユーザ。テナント選択画面はスキップされる
  member = upsert_user("member@example.com", password)
  join(sample, member, "一般ユーザ", :member)

  puts "ログイン (所属2件、選択画面あり): #{admin.email} / #{password}"
  puts "ログイン (所属1件、選択画面なし): #{member.email} / #{password}"
end
