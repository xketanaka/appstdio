class EnableRowLevelSecurityOnAdminUsers < ActiveRecord::Migration[8.1]
  def up
    # ポリシーを1つも張らないことで、利用テナント側の接続からは 0 件になる。
    # 所有者ロール（システム管理画面が使う）は RLS を素通りするので参照できる
    execute "ALTER TABLE admin_users ENABLE ROW LEVEL SECURITY;"
  end

  def down
    execute "ALTER TABLE admin_users DISABLE ROW LEVEL SECURITY;"
  end
end
