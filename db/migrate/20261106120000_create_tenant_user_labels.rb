class CreateTenantUserLabels < ActiveRecord::Migration[8.1]
  TENANT_SCOPED = ["tenant_user_labels", "tenant_user_labelings"].freeze

  def up
    create_table :tenant_user_labels do |t|
      t.references :tenant, type: :uuid, null: false, foreign_key: { on_delete: :cascade }, index: false
      t.string :name, null: false
      t.timestamps

      t.index [:tenant_id, :name], unique: true
    end

    create_table :tenant_user_labelings do |t|
      t.references :tenant, type: :uuid, null: false, foreign_key: { on_delete: :cascade }
      t.references :tenant_user, null: false, foreign_key: { on_delete: :cascade }, index: false
      t.references :tenant_user_label, null: false, foreign_key: { on_delete: :cascade }
      t.timestamps

      t.index [:tenant_user_id, :tenant_user_label_id], unique: true
    end

    TENANT_SCOPED.each do |table|
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
    drop_table :tenant_user_labelings
    drop_table :tenant_user_labels
  end
end
