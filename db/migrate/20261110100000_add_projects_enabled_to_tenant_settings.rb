class AddProjectsEnabledToTenantSettings < ActiveRecord::Migration[8.1]
  def change
    add_column :tenant_settings, :projects_enabled, :boolean, null: false, default: false
  end
end
