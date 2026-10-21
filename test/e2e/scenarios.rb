# E2E テストのデータ。テストごとに専用のテナントを作るので、テスト同士がデータで干渉しない
# （RLS で他のテナントの行は見えない）。DB は流し始める前に作り直すだけで、後片付けはしない
module E2eScenarios
  PASSWORD = "password1234".freeze

  module_function

  # 組織共有ドライブ: 営業/見積、人事。オーナーと一般の利用者が1人ずつ。
  # 人事は一般さんが作って全員を打ち消してあり、オーナーは特権モードでないと開けない
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
      Files::Drive.personal_root(owner)

      {
        owner: { email: owner_user.email, password: PASSWORD },
        member: { email: member_user.email, password: PASSWORD },
        folders: { sales: sales.id, estimates: estimates.id, hr: hr.id },
      }
    end
  end
end
