class CreateFilesTables < ActiveRecord::Migration[8.1]
  def change
    create_table :files_settings do |t|
      t.references :tenant, type: :uuid, null: false,
        foreign_key: { on_delete: :cascade }, index: { unique: true }

      t.boolean :enabled, null: false, default: false
      t.bigint :storage_limit_bytes, null: false, default: 10.gigabytes
      t.bigint :storage_used_bytes, null: false, default: 0
      t.integer :version_retention_days

      t.timestamps

      t.check_constraint "storage_used_bytes >= 0", name: "files_settings_used_check"
      t.check_constraint "version_retention_days IS NULL OR version_retention_days > 0",
        name: "files_settings_retention_check"
    end

    create_table :files_drives do |t|
      t.references :tenant, type: :uuid, null: false,
        foreign_key: { on_delete: :cascade }, index: false
      t.string :kind, null: false
      t.references :owner, null: true,
        foreign_key: { to_table: :tenant_users, on_delete: :cascade }, index: false

      t.timestamps

      t.index :tenant_id, unique: true, where: "kind = 'shared'",
        name: "index_files_drives_on_shared_per_tenant"
      t.index :owner_id, unique: true, where: "kind = 'personal'"
      t.index :tenant_id

      t.check_constraint <<~SQL.squish, name: "files_drives_kind_check"
        (kind = 'shared' AND owner_id IS NULL) OR (kind = 'personal' AND owner_id IS NOT NULL)
      SQL
    end

    create_table :files_nodes do |t|
      t.references :tenant, type: :uuid, null: false,
        foreign_key: { on_delete: :cascade }, index: false
      t.references :drive, null: false,
        foreign_key: { to_table: :files_drives, on_delete: :cascade }, index: false
      t.references :parent, null: true,
        foreign_key: { to_table: :files_nodes, on_delete: :cascade }, index: false

      t.string :kind, null: false
      t.string :name, null: false
      t.references :creator, null: true,
        foreign_key: { to_table: :tenant_users, on_delete: :nullify }, index: false
      t.bigint :current_version_id
      t.bigint :byte_size, null: false, default: 0

      t.datetime :deleted_at
      t.bigint :deleted_root_id
      t.references :deleted_by, null: true,
        foreign_key: { to_table: :tenant_users, on_delete: :nullify }, index: false
      t.datetime :purge_after
      t.datetime :purged_at

      t.timestamps

      t.index :drive_id, unique: true, where: "parent_id IS NULL",
        name: "index_files_nodes_on_root_per_drive"
      t.index [:parent_id, :name], unique: true,
        where: "deleted_at IS NULL AND parent_id IS NOT NULL"
      t.index [:drive_id, :parent_id]
      t.index :deleted_root_id
      t.index :tenant_id
      t.index :current_version_id

      t.check_constraint "kind IN ('folder', 'file')", name: "files_nodes_kind_check"
    end

    create_table :files_versions do |t|
      t.references :tenant, type: :uuid, null: false,
        foreign_key: { on_delete: :cascade }, index: false
      t.references :node, null: false,
        foreign_key: { to_table: :files_nodes, on_delete: :cascade }, index: false

      t.integer :number, null: false
      t.string :label
      t.bigint :byte_size, null: false
      t.string :content_type
      t.references :creator, null: true,
        foreign_key: { to_table: :tenant_users, on_delete: :nullify }, index: false
      t.datetime :purged_at

      t.timestamps

      t.index [:node_id, :number], unique: true
      t.index :tenant_id
    end

    add_foreign_key :files_nodes, :files_versions, column: :current_version_id, on_delete: :nullify
    add_foreign_key :files_nodes, :files_nodes, column: :deleted_root_id, on_delete: :cascade

    create_table :files_permissions do |t|
      t.references :tenant, type: :uuid, null: false,
        foreign_key: { on_delete: :cascade }, index: false
      t.references :node, null: false,
        foreign_key: { to_table: :files_nodes, on_delete: :cascade }, index: false
      t.references :group, null: true, foreign_key: { on_delete: :cascade }, index: false
      t.references :tenant_user, null: true, foreign_key: { on_delete: :cascade }, index: false

      t.string :role, null: false

      t.timestamps

      t.index [:node_id, :group_id], unique: true, where: "group_id IS NOT NULL"
      t.index [:node_id, :tenant_user_id], unique: true, where: "tenant_user_id IS NOT NULL"
      t.index :group_id
      t.index :tenant_user_id
      t.index :tenant_id

      t.check_constraint "(group_id IS NULL) <> (tenant_user_id IS NULL)",
        name: "files_permissions_subject_check"
      t.check_constraint "role IN ('viewer', 'editor', 'manager', 'none')",
        name: "files_permissions_role_check"
    end

    create_table :files_activities do |t|
      t.references :tenant, type: :uuid, null: false,
        foreign_key: { on_delete: :cascade }, index: false
      t.references :node, null: true,
        foreign_key: { to_table: :files_nodes, on_delete: :nullify }, index: false
      t.references :actor, null: true,
        foreign_key: { to_table: :tenant_users, on_delete: :nullify }, index: false

      t.string :action, null: false
      t.jsonb :detail, null: false, default: {}
      t.datetime :created_at, null: false

      t.index [:tenant_id, :created_at]
      t.index [:node_id, :created_at]

      t.check_constraint <<~SQL.squish, name: "files_activities_action_check"
        action IN ('created', 'updated', 'renamed', 'moved',
                   'deleted', 'restored', 'purged', 'shared')
      SQL
    end
  end
end
