class CreateAdminUsers < ActiveRecord::Migration[8.1]
  def change
    create_table :admin_users do |t|
      t.references :user,
        null: false,
        foreign_key: { on_delete: :cascade },
        index: { unique: true }

      t.string :display_name, null: false
      t.string :status, null: false, default: "active"

      t.timestamps

      t.check_constraint "status IN ('active', 'suspended')", name: "admin_users_status_check"
    end
  end
end
