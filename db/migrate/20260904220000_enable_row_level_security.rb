class EnableRowLevelSecurity < ActiveRecord::Migration[8.1]
  # テナントスコープのテーブルに RLS を適用する。
  #
  # ポリシーは PostgreSQL のセッション変数を参照する。
  #   app.tenant_id : 現在操作しているテナント
  #   app.user_id   : 現在ログインしているユーザ
  #
  # 未設定なら current_setting(..., true) が NULL を返し、比較結果も NULL になるため
  # 1行も一致しない。設定漏れは「他テナントが見える」ではなく「0件」になる (fail-closed)。
  # NULLIF を挟んでいるのは、空文字にリセットされた場合に ''::uuid のキャストで
  # エラーにせず NULL として扱うため。
  def up
    execute <<~SQL
      ALTER TABLE tenant_users ENABLE ROW LEVEL SECURITY;

      -- 参照: 現在のテナントの所属情報、または自分自身の所属情報。
      -- 後者はログイン直後に「自分が所属するテナント一覧」を引くために必要
      -- (この時点ではまだテナントが確定していない)。
      CREATE POLICY tenant_users_select ON tenant_users
        FOR SELECT
        USING (
          tenant_id = NULLIF(current_setting('app.tenant_id', true), '')::uuid
          OR user_id = NULLIF(current_setting('app.user_id', true), '')::bigint
        );

      -- 更新系は現在のテナントに限定する。
      -- WITH CHECK が無いと他テナントの行を作れてしまうので必ず付ける。
      CREATE POLICY tenant_users_insert ON tenant_users
        FOR INSERT
        WITH CHECK (tenant_id = NULLIF(current_setting('app.tenant_id', true), '')::uuid);

      CREATE POLICY tenant_users_update ON tenant_users
        FOR UPDATE
        USING (tenant_id = NULLIF(current_setting('app.tenant_id', true), '')::uuid)
        WITH CHECK (tenant_id = NULLIF(current_setting('app.tenant_id', true), '')::uuid);

      CREATE POLICY tenant_users_delete ON tenant_users
        FOR DELETE
        USING (tenant_id = NULLIF(current_setting('app.tenant_id', true), '')::uuid);
    SQL
  end

  def down
    execute <<~SQL
      DROP POLICY IF EXISTS tenant_users_delete ON tenant_users;
      DROP POLICY IF EXISTS tenant_users_update ON tenant_users;
      DROP POLICY IF EXISTS tenant_users_insert ON tenant_users;
      DROP POLICY IF EXISTS tenant_users_select ON tenant_users;
      ALTER TABLE tenant_users DISABLE ROW LEVEL SECURITY;
    SQL
  end
end
