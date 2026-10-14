class CreateTenantSettings < ActiveRecord::Migration[8.1]
  def up
    create_table :tenant_settings do |t|
      t.references :tenant, type: :uuid, null: false,
        foreign_key: { on_delete: :cascade }, index: { unique: true }

      t.string :title_label
      t.string :title_color

      t.timestamps

      t.check_constraint "title_color ~ '^#[0-9a-f]{6}$'", name: "tenant_settings_title_color_check"
    end

    execute <<~SQL
      ALTER TABLE tenant_settings ENABLE ROW LEVEL SECURITY;

      CREATE POLICY tenant_settings_select ON tenant_settings
        FOR SELECT TO appstdio_app
        USING (tenant_id = NULLIF(current_setting('app.tenant_id', true), '')::uuid);

      CREATE POLICY tenant_settings_insert ON tenant_settings
        FOR INSERT TO appstdio_app
        WITH CHECK (tenant_id = NULLIF(current_setting('app.tenant_id', true), '')::uuid);

      CREATE POLICY tenant_settings_update ON tenant_settings
        FOR UPDATE TO appstdio_app
        USING (tenant_id = NULLIF(current_setting('app.tenant_id', true), '')::uuid)
        WITH CHECK (tenant_id = NULLIF(current_setting('app.tenant_id', true), '')::uuid);

      CREATE POLICY tenant_settings_delete ON tenant_settings
        FOR DELETE TO appstdio_app
        USING (tenant_id = NULLIF(current_setting('app.tenant_id', true), '')::uuid);

      INSERT INTO tenant_settings (tenant_id, created_at, updated_at)
      SELECT id, now(), now() FROM tenants;

      INSERT INTO files_settings (tenant_id, enabled, created_at, updated_at)
      SELECT tenants.id, true, now(), now()
      FROM tenants
      WHERE NOT EXISTS (SELECT 1 FROM files_settings WHERE files_settings.tenant_id = tenants.id);
    SQL
  end

  def down
    drop_table :tenant_settings
  end
end
