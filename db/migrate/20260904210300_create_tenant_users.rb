class CreateTenantUsers < ActiveRecord::Migration[8.1]
  def change
    create_table :tenant_users do |t|
      # 単独の tenant_id インデックスは下の複合ユニークが兼ねるため作らない
      t.references :tenant,
        type: :uuid,
        null: false,
        foreign_key: { on_delete: :cascade },
        index: false
      t.references :user,
        null: false,
        foreign_key: { on_delete: :cascade },
        index: false

      t.string :display_name, null: false
      t.string :role, null: false, default: "member"
      t.string :status, null: false, default: "invited"

      t.timestamps

      t.index [:tenant_id, :user_id], unique: true
      t.index [:user_id, :tenant_id]

      t.check_constraint "role IN ('owner', 'admin', 'member')", name: "tenant_users_role_check"
      t.check_constraint "status IN ('invited', 'active', 'suspended')", name: "tenant_users_status_check"
    end
  end
end
