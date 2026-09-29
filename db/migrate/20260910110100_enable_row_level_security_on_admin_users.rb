class EnableRowLevelSecurityOnAdminUsers < ActiveRecord::Migration[8.1]
  def up
    execute "ALTER TABLE admin_users ENABLE ROW LEVEL SECURITY;"
  end

  def down
    execute "ALTER TABLE admin_users DISABLE ROW LEVEL SECURITY;"
  end
end
