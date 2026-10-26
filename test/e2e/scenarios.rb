# E2E テストのデータ。テストのファイルごとに専用のテナントを作るので、ファイル同士がデータで干渉しない
# （RLS で他のテナントの行は見えない）。DB は流し始める前に作り直すだけで、後片付けはしない
module E2eScenarios
  PASSWORD = "password1234".freeze

  module_function

  # オーナーと、全社 > 開発部。開発部のメンバーは 70人。ログインしない人たちなので、
  # パスワードを1つだけ作って使い回す（1人ずつ作るとハッシュの計算で遅くなる）
  def groups
    key = SecureRandom.hex(4)
    tenant = Tenant.setup!(name: "E2E #{key}")
    owner_user = User.create!(email: "owner-#{key}@example.com", password: PASSWORD)
    digest = BCrypt::Password.create(PASSWORD, cost: BCrypt::Engine::MIN_COST)
    user_ids = User.insert_all!(
      Array.new(70) { |i| { email: "dev#{i}-#{key}@example.com", password_digest: digest } }, returning: :id
    ).rows.flatten

    TenantContext.switch(tenant: tenant) do
      TenantUser.create!(tenant:, user: owner_user, display_name: "管理者さん", role: :owner, status: :active)
      company = Group.create!(tenant:, name: "全社")
      dev = Group.create!(tenant:, parent: company, name: "開発部")
      tenant_user_ids = TenantUser.insert_all!(
        user_ids.each_with_index.map do |user_id, i|
          { tenant_id: tenant.id, user_id:, display_name: format("開発 %02d", i), role: "member", status: "active" }
        end,
        returning: :id
      ).rows.flatten
      GroupMember.insert_all!(tenant_user_ids.map { { tenant_id: tenant.id, group_id: dev.id, tenant_user_id: it } })

      { owner: { email: owner_user.email, password: PASSWORD }, groups: { company: company.id } }
    end
  end

  # 組織共有ドライブ: 営業/見積、人事。オーナーと一般の利用者が1人ずつ。
  # 人事は一般さんが作って全員を打ち消してあり、オーナーは特権モードでないと開けない。
  # オーナーのマイドライブ: 下書き、メモ.txt、保管（ダイアログでの移動で使う）、
  # 資料、議事録.txt（ドラッグでの移動で使う）、変更前.txt、不要.txt（名前の変更・削除・復元で使う）
  def files
    key = SecureRandom.hex(4)
    tenant = Tenant.setup!(name: "E2E #{key}")
    owner_user = User.create!(email: "owner-#{key}@example.com", password: PASSWORD)
    member_user = User.create!(email: "member-#{key}@example.com", password: PASSWORD)

    TenantContext.switch(tenant: tenant) do
      owner = TenantUser.create!(tenant:, user: owner_user, display_name: "管理者さん", role: :owner, status: :active)
      member = TenantUser.create!(tenant:, user: member_user, display_name: "一般さん", role: :member, status: :active)

      root = Files::Drive.shared_root(tenant)
      sales = Files::Node.create_folder!(parent: root, name: "営業", creator: owner)
      estimates = Files::Node.create_folder!(parent: sales, name: "見積", creator: owner)
      hr = Files::Node.create_folder!(parent: root, name: "人事", creator: member)
      Files::Permission.create!(tenant:, node: hr, group: Group.everyone_of(tenant), role: :none)
      my_drive = Files::Drive.personal_root(owner)
      %w[下書き 保管 資料].each { Files::Node.create_folder!(parent: my_drive, name: it, creator: owner) }
      %w[メモ.txt 議事録.txt 変更前.txt 不要.txt].each do |name|
        blob = ActiveStorage::Blob.create_and_upload!(io: StringIO.new("#{name} の中身"), filename: name)
        Files::Node.create_file!(parent: my_drive, blob:, creator: owner)
      end

      {
        owner: { email: owner_user.email, password: PASSWORD },
        member: { email: member_user.email, password: PASSWORD },
        folders: { sales: sales.id, estimates: estimates.id, hr: hr.id },
      }
    end
  end
end
