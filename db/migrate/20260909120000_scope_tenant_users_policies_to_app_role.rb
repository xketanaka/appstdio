class ScopeTenantUsersPoliciesToAppRole < ActiveRecord::Migration[8.1]
  POLICIES = %w[
    tenant_users_select
    tenant_users_insert
    tenant_users_update
    tenant_users_delete
  ].freeze

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
