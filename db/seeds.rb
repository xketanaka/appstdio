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
    membership
  end

  def group(tenant, name, parent = nil)
    Group.find_or_create_by!(tenant: tenant, parent: parent, name: name)
  end

  def node(parent, kind, name, creator, byte_size: 0)
    Files::Node.kept.find_or_create_by!(parent: parent, name: name) do |node|
      node.assign_attributes(tenant: parent.tenant, drive: parent.drive, kind: kind, creator: creator, byte_size: byte_size)
    end
  end

  def grant(node, subject, role)
    subject_key = subject.is_a?(Group) ? :group : :tenant_user
    Files::Permission.find_or_initialize_by(node: node, subject_key => subject).update!(tenant: node.tenant, role: role)
  end

  sample = Tenant.find_or_create_by!(name: "サンプル株式会社")
  test = Tenant.find_or_create_by!(name: "テスト工業")

  admin = upsert_user("admin@example.com", password)
  sample_admin = join(sample, admin, "管理者", :owner)
  join(test, admin, "管理者", :member)

  member = upsert_user("member@example.com", password)
  sample_member = join(sample, member, "一般ユーザ", :member)

  sales = group(sample, "営業部")
  sales1 = group(sample, "営業1課", sales)
  GroupMember.find_or_create_by!(tenant: sample, group: sales1, tenant_user: sample_member)

  shared = Files::Drive.shared_root(sample)
  sales_folder = node(shared, :folder, "営業", sample_admin)
  grant(sales_folder, sales, :editor)
  estimates = node(sales_folder, :folder, "見積", sample_admin)
  node(estimates, :file, "見積書_A社.pdf", sample_member, byte_size: 1_258_291)
  hr = node(shared, :folder, "人事", sample_admin)
  grant(hr, Group.everyone_of(sample), :none)
  review = node(hr, :file, "評価シート.xlsx", sample_admin, byte_size: 48_128)
  grant(review, sample_member, :viewer)
  node(shared, :file, "議事録.docx", sample_admin, byte_size: 25_088)
  unless Files::Node.trashed.exists?(parent: sales_folder, name: "古い見積.pdf")
    old = node(sales_folder, :file, "古い見積.pdf", sample_member, byte_size: 512_000)
    old.update!(deleted_at: Time.current, deleted_root_id: old.id, deleted_by: sample_member)
  end
  node(Files::Drive.personal_root(sample_member), :file, "メモ.txt", sample_member, byte_size: 1_024)

  operator = upsert_user("operator@example.com", password)
  account = AdminUser.find_or_initialize_by(user_id: operator.id)
  account.display_name = "運用担当"
  account.status = :active
  account.save!

  puts "ログイン (所属2件、選択画面あり): #{admin.email} / #{password}"
  puts "ログイン (所属1件、選択画面なし): #{member.email} / #{password}"
  puts "管理画面 /admin/login              : #{operator.email} / #{password}"
end
