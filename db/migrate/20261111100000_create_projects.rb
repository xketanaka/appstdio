class CreateProjects < ActiveRecord::Migration[8.1]
  def up
    execute <<~SQL
      ALTER TABLE groups DROP CONSTRAINT groups_kind_check;
      ALTER TABLE groups ADD CONSTRAINT groups_kind_check
        CHECK (kind IN ('department', 'everyone', 'project_root', 'project'));
    SQL
    add_index :groups, :tenant_id, unique: true, where: "kind = 'project_root'", name: "index_groups_on_project_root_per_tenant"

    create_table :projects do |t|
      t.references :tenant, type: :uuid, null: false, foreign_key: { on_delete: :cascade }
      # グループを消すとプロジェクトも消える（プロジェクトの削除はグループを消して行う）
      t.references :group, null: false, foreign_key: { on_delete: :cascade }, index: { unique: true }
      t.timestamps
    end

    execute <<~SQL
      ALTER TABLE projects ENABLE ROW LEVEL SECURITY;

      CREATE POLICY projects_select ON projects
        FOR SELECT TO appstdio_app
        USING (tenant_id = NULLIF(current_setting('app.tenant_id', true), '')::uuid);

      CREATE POLICY projects_insert ON projects
        FOR INSERT TO appstdio_app
        WITH CHECK (tenant_id = NULLIF(current_setting('app.tenant_id', true), '')::uuid);

      CREATE POLICY projects_update ON projects
        FOR UPDATE TO appstdio_app
        USING (tenant_id = NULLIF(current_setting('app.tenant_id', true), '')::uuid)
        WITH CHECK (tenant_id = NULLIF(current_setting('app.tenant_id', true), '')::uuid);

      CREATE POLICY projects_delete ON projects
        FOR DELETE TO appstdio_app
        USING (tenant_id = NULLIF(current_setting('app.tenant_id', true), '')::uuid);

      -- すでにプロジェクト機能を利用するにしているテナントに、最上位の「プロジェクト」を作る。
      -- 同じ名前の最上位のグループがあるテナントは作らない（プロジェクトを作るときに案内する）
      INSERT INTO groups (tenant_id, kind, name, created_at, updated_at)
      SELECT tenant_settings.tenant_id, 'project_root', 'プロジェクト', now(), now()
      FROM tenant_settings
      WHERE tenant_settings.projects_enabled
        AND NOT EXISTS (
          SELECT 1 FROM groups
          WHERE groups.tenant_id = tenant_settings.tenant_id AND groups.parent_id IS NULL
            AND groups.suspended_at IS NULL AND groups.name = 'プロジェクト'
        );
    SQL
  end

  def down
    drop_table :projects
    remove_index :groups, name: "index_groups_on_project_root_per_tenant"
    execute <<~SQL
      ALTER TABLE groups DROP CONSTRAINT groups_kind_check;
      ALTER TABLE groups ADD CONSTRAINT groups_kind_check CHECK (kind IN ('department', 'everyone'));
    SQL
  end
end
