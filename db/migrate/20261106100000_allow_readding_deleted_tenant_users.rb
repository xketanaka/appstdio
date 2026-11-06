class AllowReaddingDeletedTenantUsers < ActiveRecord::Migration[8.1]
  def change
    remove_index :tenant_users, [:tenant_id, :user_id], unique: true
    add_index :tenant_users, [:tenant_id, :user_id], unique: true, where: "status <> 'deleted'"
  end
end
