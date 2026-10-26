class RestrictTenantUsersSelectToTenant < ActiveRecord::Migration[8.1]
  def up
    execute <<~SQL
      ALTER POLICY tenant_users_select ON tenant_users
        USING (tenant_id = NULLIF(current_setting('app.tenant_id', true), '')::uuid);

      -- 所有者の権限で動くので RLS を通らない。返すのは app.user_id の行だけで、未設定なら0件
      CREATE FUNCTION own_memberships() RETURNS SETOF tenant_users
        LANGUAGE sql STABLE SECURITY DEFINER
        SET search_path = pg_catalog, public
        AS $$
          SELECT * FROM tenant_users
           WHERE user_id = NULLIF(current_setting('app.user_id', true), '')::bigint
        $$;
    SQL
  end

  def down
    execute <<~SQL
      DROP FUNCTION own_memberships();

      ALTER POLICY tenant_users_select ON tenant_users
        USING (tenant_id = NULLIF(current_setting('app.tenant_id', true), '')::uuid
               OR user_id = NULLIF(current_setting('app.user_id', true), '')::bigint);
    SQL
  end
end
