require "test_helper"

# RLS が「効いているつもりで実は素通り」になっていないことを確認する。
# ここが落ちている状態では RowLevelSecurityTest が通っても意味がない。
class RlsConfigurationTest < ActiveSupport::TestCase
  test "接続ロールは RLS をバイパスしない" do
    role = ApplicationRecord.with_connection do |connection|
      connection.select_one(<<~SQL)
        SELECT rolsuper, rolbypassrls FROM pg_roles WHERE rolname = current_user
      SQL
    end

    assert_equal false, role["rolsuper"], "接続ロールがスーパーユーザです。RLS は適用されません"
    assert_equal false, role["rolbypassrls"], "接続ロールが BYPASSRLS を持っています"
  end

  test "接続ロールはテーブルの所有者ではない" do
    owned = ApplicationRecord.with_connection do |connection|
      connection.select_values(<<~SQL)
        SELECT tablename FROM pg_tables
         WHERE schemaname = 'public' AND tableowner = current_user
      SQL
    end

    assert_empty owned,
      "接続ロールが所有しているテーブルには RLS が適用されません: #{owned.join(", ")}"
  end

  test "tenant_id を持つテーブルは必ず RLS が有効になっている" do
    unprotected = ApplicationRecord.with_connection do |connection|
      connection.select_values(<<~SQL)
        SELECT c.relname
          FROM pg_class c
          JOIN pg_namespace n ON n.oid = c.relnamespace
          JOIN pg_attribute a ON a.attrelid = c.oid
         WHERE n.nspname = 'public'
           AND c.relkind = 'r'
           AND a.attname = 'tenant_id'
           AND a.attnum > 0
           AND NOT a.attisdropped
           AND NOT c.relrowsecurity
         ORDER BY c.relname
      SQL
    end

    assert_empty unprotected,
      "RLS が有効になっていないテナントスコープのテーブルがあります: #{unprotected.join(", ")}"
  end
end
