-- RLS のためのロール構成。詳細は docker/README.md を参照。
--
--   appstdio_owner : テーブルを所有する。マイグレーションとシステム管理画面が使う
--   appstdio_app   : 利用テナント側のアプリが接続する。RLS が適用される
--
-- postgres コンテナの初回起動時 (/docker-entrypoint-initdb.d) に実行される。
-- 既存ボリュームへ手で流す場合を想定して冪等に書いている。

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'appstdio_owner') THEN
    -- db:create / db:test:prepare のために CREATEDB が必要
    CREATE ROLE appstdio_owner LOGIN PASSWORD 'owner_password' CREATEDB;
  END IF;

  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'appstdio_app') THEN
    CREATE ROLE appstdio_app LOGIN PASSWORD 'app_password';
  END IF;
END
$$;

-- 既存ロールに対しても RLS をすり抜ける属性が付いていないことを保証する
ALTER ROLE appstdio_app NOSUPERUSER NOBYPASSRLS NOCREATEDB NOCREATEROLE;

-- template1 に仕込むことで、以後 db:create で作られる DB に引き継がれる。
-- 無いとマイグレーションで追加したテーブルに appstdio_app がアクセスできない。
\connect template1

ALTER DEFAULT PRIVILEGES FOR ROLE appstdio_owner IN SCHEMA public
  GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO appstdio_app;

ALTER DEFAULT PRIVILEGES FOR ROLE appstdio_owner IN SCHEMA public
  GRANT USAGE, SELECT ON SEQUENCES TO appstdio_app;
