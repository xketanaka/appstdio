class AddSuspensionToTenantUsers < ActiveRecord::Migration[8.1]
  def change
    add_column :tenant_users, :suspended_at, :datetime
    add_reference :tenant_users, :suspended_by, foreign_key: { to_table: :tenant_users, on_delete: :nullify }, index: false

    # 利用停止の操作ができる前に停止中にした行は、いつ止めたかが分からないので、最後に更新した日時で代える
    reversible do |dir|
      dir.up { execute "UPDATE tenant_users SET suspended_at = updated_at WHERE status = 'suspended'" }
    end
  end
end
