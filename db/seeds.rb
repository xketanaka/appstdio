# This file should ensure the existence of records required to run the application in every environment (production,
# development, test). The code here should be idempotent so that it can be executed at any point in every environment.
# The data can then be loaded with the bin/rails db:seed command (or created alongside the database with db:setup).
#
# RLS があるため、所有者ロールで実行すること。
#
#   bin/rails-as-owner db:seed

if Rails.env.local?
  password = "password1234"

  def upsert_user(email, password)
    User.find_or_initialize_by(email: email).tap do |user|
      user.password = password if user.new_record?
      user.save!
    end
  end

  def join(tenant, user, display_name, role)
    membership = TenantUser.find_or_initialize_by(tenant_id: tenant.id, user_id: user.id)
    membership.display_name = display_name
    membership.role = role
    membership.status = :active
    membership.save!
  end

  sample = Tenant.find_or_create_by!(name: "サンプル株式会社")
  test = Tenant.find_or_create_by!(name: "テスト工業")

  admin = upsert_user("admin@example.com", password)
  join(sample, admin, "管理者", :owner)
  join(test, admin, "管理者", :member)

  member = upsert_user("member@example.com", password)
  join(sample, member, "一般ユーザ", :member)

  operator = Operator.find_or_initialize_by(email: "operator@example.com")
  operator.password = password if operator.new_record?
  operator.display_name = "運用担当"
  operator.status = :active
  operator.save!

  puts "ログイン (所属2件、選択画面あり): #{admin.email} / #{password}"
  puts "ログイン (所属1件、選択画面なし): #{member.email} / #{password}"
  puts "管理画面 /ops/login                : #{operator.email} / #{password}"
end
