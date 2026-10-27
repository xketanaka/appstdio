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

  def folder(parent, name, creator)
    Files::Node.kept.find_by(parent:, name:) || Files::Node.create_folder!(parent:, name:, creator:)
  end

  # ファイルは中身（版1）ごと作る。中身の無いファイルは、画面から作れない不整合なデータになる
  # rake の file（ファイルのタスクを作る）とぶつかるので、名前を変えている
  def sample_file(parent, name, creator, content)
    Files::Node.kept.find_by(parent:, name:) || Files::Node.create_file!(
      parent:, creator:, blob: ActiveStorage::Blob.create_and_upload!(io: StringIO.new(content), filename: name),
    )
  end

  # 1ページに1行だけ書いた PDF。PDF のビューアで開ける最小の形
  def pdf(text)
    stream = "BT /F1 24 Tf 72 760 Td (#{text}) Tj ET"
    objects = [
      "<< /Type /Catalog /Pages 2 0 R >>",
      "<< /Type /Pages /Kids [3 0 R] /Count 1 >>",
      "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 595 842] /Contents 4 0 R /Resources << /Font << /F1 5 0 R >> >> >>",
      "<< /Length #{stream.bytesize} >>\nstream\n#{stream}\nendstream",
      "<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>",
    ]
    body = +"%PDF-1.4\n"
    offsets = objects.each_with_index.map do |object, i|
      body.bytesize.tap { body << "#{i + 1} 0 obj\n#{object}\nendobj\n" }
    end
    xref = body.bytesize
    body << "xref\n0 #{objects.size + 1}\n0000000000 65535 f \n"
    offsets.each { body << format("%010d 00000 n \n", it) }
    body << "trailer\n<< /Size #{objects.size + 1} /Root 1 0 R >>\nstartxref\n#{xref}\n%%EOF\n"
  end

  def grant(node, subject, role)
    subject_key = subject.is_a?(Group) ? :group : :tenant_user
    Files::Permission.find_or_initialize_by(node: node, subject_key => subject).update!(tenant: node.tenant, role: role)
  end

  sample = Tenant.find_by(name: "サンプル株式会社") || Tenant.setup!(name: "サンプル株式会社")
  test = Tenant.find_by(name: "テスト工業") || Tenant.setup!(name: "テスト工業")

  admin = upsert_user("admin@example.com", password)
  sample_admin = join(sample, admin, "管理者", :owner)
  join(test, admin, "管理者", :member)

  member = upsert_user("member@example.com", password)
  sample_member = join(sample, member, "一般ユーザ", :member)

  sales = group(sample, "営業部")
  sales1 = group(sample, "営業1課", sales)
  GroupMember.find_or_create_by!(tenant: sample, group: sales1, tenant_user: sample_member)

  # 以前の seed は中身（版）の無いファイルを作っていた。残っていれば消して、中身ごと作り直す
  Files::Node.file.where(current_version_id: nil).delete_all

  shared = Files::Drive.shared_root(sample)
  sales_folder = folder(shared, "営業", sample_admin)
  grant(sales_folder, sales, :editor)
  estimates = folder(sales_folder, "見積", sample_admin)
  sample_file(estimates, "見積書_A社.pdf", sample_member, pdf("Estimate for Company A"))
  hr = folder(shared, "人事", sample_admin)
  grant(hr, Group.everyone_of(sample), :none)
  review = sample_file(hr, "評価シート.csv", sample_admin, "氏名,評価\n一般ユーザ,A\n")
  grant(review, sample_member, :viewer)
  sample_file(shared, "議事録.md", sample_admin, "# 定例会議 議事録\n\n- 来期の予算について確認した\n")
  unless Files::Node.trashed.exists?(parent: sales_folder, name: "古い見積.pdf")
    Files::Node.trash!([sample_file(sales_folder, "古い見積.pdf", sample_member, pdf("Old estimate"))], actor: sample_member)
  end
  sample_file(Files::Drive.personal_root(sample_member), "メモ.txt", sample_member, "来週の打ち合わせの準備をする\n")

  operator = Operator.find_or_initialize_by(email: "operator@example.com")
  operator.password = password if operator.new_record?
  operator.display_name = "運用担当"
  operator.status = :active
  operator.save!

  puts "ログイン (所属2件、選択画面あり): #{admin.email} / #{password}"
  puts "ログイン (所属1件、選択画面なし): #{member.email} / #{password}"
  puts "運営者画面 /ops/login           : #{operator.email} / #{password}"
end
