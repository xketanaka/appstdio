class CreateProjectVisits < ActiveRecord::Migration[8.1]
  def up
    create_table :project_visits do |t|
      t.references :tenant, type: :uuid, null: false, foreign_key: { on_delete: :cascade }, index: false
      t.references :tenant_user, null: false, foreign_key: { on_delete: :cascade }, index: false
      t.references :project, null: false, foreign_key: { on_delete: :cascade }
      t.datetime :visited_at, null: false
    end
    add_index :project_visits, [:tenant_user_id, :project_id], unique: true

    execute <<~SQL
      ALTER TABLE project_visits ENABLE ROW LEVEL SECURITY;

      CREATE POLICY project_visits_select ON project_visits
        FOR SELECT TO appstdio_app
        USING (tenant_id = NULLIF(current_setting('app.tenant_id', true), '')::uuid);

      CREATE POLICY project_visits_insert ON project_visits
        FOR INSERT TO appstdio_app
        WITH CHECK (tenant_id = NULLIF(current_setting('app.tenant_id', true), '')::uuid);

      CREATE POLICY project_visits_update ON project_visits
        FOR UPDATE TO appstdio_app
        USING (tenant_id = NULLIF(current_setting('app.tenant_id', true), '')::uuid)
        WITH CHECK (tenant_id = NULLIF(current_setting('app.tenant_id', true), '')::uuid);

      CREATE POLICY project_visits_delete ON project_visits
        FOR DELETE TO appstdio_app
        USING (tenant_id = NULLIF(current_setting('app.tenant_id', true), '')::uuid);
    SQL
  end

  def down
    drop_table :project_visits
  end
end
