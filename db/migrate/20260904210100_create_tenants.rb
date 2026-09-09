class CreateTenants < ActiveRecord::Migration[8.1]
  def change
    create_table :tenants, id: :uuid, default: -> { "uuidv7()" } do |t|
      t.string :name, null: false
      t.string :status, null: false, default: "active"

      t.timestamps

      t.check_constraint "status IN ('active', 'suspended')", name: "tenants_status_check"
    end
  end
end
