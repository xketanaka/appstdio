class AddDeletedToTenantUsersStatus < ActiveRecord::Migration[8.1]
  def up
    remove_check_constraint :tenant_users, name: "tenant_users_status_check"
    add_check_constraint :tenant_users, "status IN ('invited', 'active', 'suspended', 'deleted')",
      name: "tenant_users_status_check"
  end

  def down
    remove_check_constraint :tenant_users, name: "tenant_users_status_check"
    add_check_constraint :tenant_users, "status IN ('invited', 'active', 'suspended')", name: "tenant_users_status_check"
  end
end
