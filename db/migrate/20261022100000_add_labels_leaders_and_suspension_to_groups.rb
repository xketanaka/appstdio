class AddLabelsLeadersAndSuspensionToGroups < ActiveRecord::Migration[8.1]
  TENANT_SCOPED = ["group_labels", "group_labelings"].freeze

  def up
    add_column :group_members, :role, :string, null: false, default: "member"
    add_check_constraint :group_members, "role IN ('member', 'leader')", name: "group_members_role_check"

    add_column :groups, :suspended_at, :datetime
    add_reference :groups, :suspended_by, foreign_key: { to_table: :tenant_users, on_delete: :nullify }, index: false
    add_column :groups, :suspended_path, :string, array: true
    add_reference :groups, :suspension_root, foreign_key: { to_table: :groups, on_delete: :nullify }
    add_check_constraint :groups,
      "(suspended_at IS NULL) = (suspension_root_id IS NULL) AND (suspended_at IS NULL) = (suspended_path IS NULL)",
      name: "groups_suspension_check"

    # 名前は有効なグループの間でだけ重ならないようにする
    remove_index :groups, name: "index_groups_on_tenant_id_and_parent_id_and_name"
    remove_index :groups, name: "index_groups_on_tenant_id_and_name"
    add_index :groups, [:tenant_id, :parent_id, :name], unique: true,
      where: "parent_id IS NOT NULL AND suspended_at IS NULL", name: "index_groups_on_active_name_under_parent"
    add_index :groups, [:tenant_id, :name], unique: true,
      where: "parent_id IS NULL AND suspended_at IS NULL", name: "index_groups_on_active_root_name"
    add_index :groups, [:tenant_id, :suspended_at], where: "suspended_at IS NOT NULL"

    create_table :group_labels do |t|
      t.references :tenant, type: :uuid, null: false, foreign_key: { on_delete: :cascade }, index: false
      t.string :name, null: false
      t.timestamps

      t.index [:tenant_id, :name], unique: true
    end

    create_table :group_labelings do |t|
      t.references :tenant, type: :uuid, null: false, foreign_key: { on_delete: :cascade }
      t.references :group, null: false, foreign_key: { on_delete: :cascade }, index: false
      t.references :group_label, null: false, foreign_key: { on_delete: :cascade }
      t.timestamps

      t.index [:group_id, :group_label_id], unique: true
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
    drop_table :group_labelings
    drop_table :group_labels
    remove_index :groups, name: "index_groups_on_active_root_name"
    remove_index :groups, name: "index_groups_on_active_name_under_parent"
    remove_index :groups, [:tenant_id, :suspended_at]
    add_index :groups, [:tenant_id, :parent_id, :name], unique: true, where: "parent_id IS NOT NULL"
    add_index :groups, [:tenant_id, :name], unique: true, where: "parent_id IS NULL"
    remove_check_constraint :groups, name: "groups_suspension_check"
    remove_reference :groups, :suspension_root
    remove_column :groups, :suspended_path
    remove_reference :groups, :suspended_by
    remove_column :groups, :suspended_at
    remove_check_constraint :group_members, name: "group_members_role_check"
    remove_column :group_members, :role
  end
end
