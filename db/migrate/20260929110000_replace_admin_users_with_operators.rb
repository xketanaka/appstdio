class ReplaceAdminUsersWithOperators < ActiveRecord::Migration[8.1]
  def up
    create_table :operators do |t|
      t.citext :email, null: false
      t.string :password_digest, null: false
      t.string :display_name, null: false
      t.string :status, null: false, default: "active"
      t.datetime :last_signed_in_at

      t.timestamps

      t.index :email, unique: true
      t.check_constraint "status IN ('active', 'suspended')", name: "operators_status_check"
    end

    # ポリシーを張らないことで、利用テナント側のロールからは 0 件になる。FORCE は付けない
    execute "ALTER TABLE operators ENABLE ROW LEVEL SECURITY;"

    drop_table :admin_users
  end

  def down
    raise ActiveRecord::IrreversibleMigration
  end
end
