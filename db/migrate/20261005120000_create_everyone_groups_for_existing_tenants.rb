class CreateEveryoneGroupsForExistingTenants < ActiveRecord::Migration[8.1]
  def up
    execute <<~SQL
      INSERT INTO groups (tenant_id, kind, name, created_at, updated_at)
      SELECT tenants.id, 'everyone', #{connection.quote(I18n.t("groups.everyone"))}, now(), now()
      FROM tenants
      WHERE NOT EXISTS (SELECT 1 FROM groups WHERE groups.tenant_id = tenants.id AND groups.kind = 'everyone')
    SQL
  end

  def down
  end
end
