class EnableRowLevelSecurityOnFilesTables < ActiveRecord::Migration[8.1]
  TABLES = %w[
    groups
    group_members
    files_settings
    files_drives
    files_nodes
    files_versions
    files_permissions
    files_activities
  ].freeze

  def up
    TABLES.each do |table|
      execute <<~SQL
        ALTER TABLE #{table} ENABLE ROW LEVEL SECURITY;

        CREATE POLICY #{table}_select ON #{table}
          FOR SELECT TO appstdio_app
          USING (tenant_id = NULLIF(current_setting('app.tenant_id', true), '')::uuid);

        CREATE POLICY #{table}_insert ON #{table}
          FOR INSERT TO appstdio_app
          WITH CHECK (tenant_id = NULLIF(current_setting('app.tenant_id', true), '')::uuid);

        CREATE POLICY #{table}_update ON #{table}
          FOR UPDATE TO appstdio_app
          USING (tenant_id = NULLIF(current_setting('app.tenant_id', true), '')::uuid)
          WITH CHECK (tenant_id = NULLIF(current_setting('app.tenant_id', true), '')::uuid);

        CREATE POLICY #{table}_delete ON #{table}
          FOR DELETE TO appstdio_app
          USING (tenant_id = NULLIF(current_setting('app.tenant_id', true), '')::uuid);
      SQL
    end
  end

  def down
    TABLES.each do |table|
      execute <<~SQL
        DROP POLICY IF EXISTS #{table}_delete ON #{table};
        DROP POLICY IF EXISTS #{table}_update ON #{table};
        DROP POLICY IF EXISTS #{table}_insert ON #{table};
        DROP POLICY IF EXISTS #{table}_select ON #{table};
        ALTER TABLE #{table} DISABLE ROW LEVEL SECURITY;
      SQL
    end
  end
end
