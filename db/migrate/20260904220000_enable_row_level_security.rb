class EnableRowLevelSecurity < ActiveRecord::Migration[8.1]
  def up
    execute <<~SQL
      ALTER TABLE tenant_users ENABLE ROW LEVEL SECURITY;

      CREATE POLICY tenant_users_select ON tenant_users
        FOR SELECT
        USING (
          tenant_id = NULLIF(current_setting('app.tenant_id', true), '')::uuid
          OR user_id = NULLIF(current_setting('app.user_id', true), '')::bigint
        );

      CREATE POLICY tenant_users_insert ON tenant_users
        FOR INSERT
        WITH CHECK (tenant_id = NULLIF(current_setting('app.tenant_id', true), '')::uuid);

      CREATE POLICY tenant_users_update ON tenant_users
        FOR UPDATE
        USING (tenant_id = NULLIF(current_setting('app.tenant_id', true), '')::uuid)
        WITH CHECK (tenant_id = NULLIF(current_setting('app.tenant_id', true), '')::uuid);

      CREATE POLICY tenant_users_delete ON tenant_users
        FOR DELETE
        USING (tenant_id = NULLIF(current_setting('app.tenant_id', true), '')::uuid);
    SQL
  end

  def down
    execute <<~SQL
      DROP POLICY IF EXISTS tenant_users_delete ON tenant_users;
      DROP POLICY IF EXISTS tenant_users_update ON tenant_users;
      DROP POLICY IF EXISTS tenant_users_insert ON tenant_users;
      DROP POLICY IF EXISTS tenant_users_select ON tenant_users;
      ALTER TABLE tenant_users DISABLE ROW LEVEL SECURITY;
    SQL
  end
end
