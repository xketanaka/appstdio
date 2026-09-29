class CreateGroups < ActiveRecord::Migration[8.1]
  def change
    create_table :groups do |t|
      t.references :tenant, type: :uuid, null: false,
        foreign_key: { on_delete: :cascade }, index: false
      t.references :parent, null: true, foreign_key: { to_table: :groups, on_delete: :cascade },
        index: false

      t.string :kind, null: false, default: "department"
      t.string :name, null: false

      t.timestamps

      t.index [:tenant_id, :parent_id, :name], unique: true, where: "parent_id IS NOT NULL"
      t.index [:tenant_id, :name], unique: true, where: "parent_id IS NULL"
      t.index :tenant_id, unique: true, where: "kind = 'everyone'",
        name: "index_groups_on_everyone_per_tenant"
      t.index [:tenant_id, :parent_id]

      t.check_constraint "kind IN ('department', 'everyone')", name: "groups_kind_check"
    end

    create_table :group_members do |t|
      t.references :tenant, type: :uuid, null: false,
        foreign_key: { on_delete: :cascade }, index: false
      t.references :group, null: false, foreign_key: { on_delete: :cascade }, index: false
      t.references :tenant_user, null: false, foreign_key: { on_delete: :cascade }, index: false

      t.timestamps

      t.index [:group_id, :tenant_user_id], unique: true
      t.index :tenant_user_id
      t.index :tenant_id
    end
  end
end
