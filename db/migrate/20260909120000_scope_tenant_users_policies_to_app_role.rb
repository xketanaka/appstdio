class ScopeTenantUsersPoliciesToAppRole < ActiveRecord::Migration[8.1]
  POLICIES = %w[
    tenant_users_select
    tenant_users_insert
    tenant_users_update
    tenant_users_delete
  ].freeze

  # ポリシーは permissive (OR 結合) なので、TO を省略して PUBLIC 宛にしておくと
  # 後から追加したロールにもこのポリシーが効いてしまう
  def up
    POLICIES.each do |policy|
      execute "ALTER POLICY #{policy} ON tenant_users TO appstdio_app;"
    end
  end

  def down
    POLICIES.each do |policy|
      execute "ALTER POLICY #{policy} ON tenant_users TO public;"
    end
  end
end
