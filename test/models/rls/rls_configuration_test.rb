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

  test "admin_users は利用テナント側のロールから参照できない" do
    rls, roles = ApplicationRecord.with_connection do |connection|
      [
        connection.select_value("SELECT relrowsecurity FROM pg_class WHERE relname = 'admin_users'"),
        connection.select_values(
          "SELECT unnest(roles)::text FROM pg_policies WHERE tablename = 'admin_users'",
        ),
      ]
    end

    assert_equal true, rls, "admin_users の RLS が無効になっている"
    assert_not_includes roles, ENV.fetch("DB_USER", "appstdio_app"),
      "利用テナント側のロール向けのポリシーがあると、管理者の一覧が参照できてしまう"
    assert_not_includes roles, "public"
    # 所有者ロール（管理画面）は RLS を素通りするので、ポリシーは不要
    assert_equal false, ApplicationRecord.with_connection { |c|
      c.select_value("SELECT relforcerowsecurity FROM pg_class WHERE relname = 'admin_users'")
    }, "FORCE を付けると所有者にも RLS が適用され、管理画面から参照できなくなる"
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

  test "ポリシーの適用先が public のままになっていない" do
    policies = ApplicationRecord.with_connection do |connection|
      connection.select_values(<<~SQL)
        SELECT tablename || '.' || policyname
          FROM pg_policies
         WHERE schemaname = 'public' AND 'public' = ANY(roles)
         ORDER BY 1
      SQL
    end

    assert_empty policies,
      "ポリシーは permissive (OR 結合) なので、PUBLIC 宛だと後から追加した" \
      "テナント束縛ロールにも適用され、束縛が効かなくなります: #{policies.join(", ")}"
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
