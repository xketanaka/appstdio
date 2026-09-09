-- RLS のためのロール構成。
--
-- PostgreSQL は「スーパーユーザ」と「テーブルの所有者」には RLS を適用しない。
-- そのためアプリの接続ロールを、テーブルを所有するロールから分離する必要がある。
--
--   appstdio_owner : テーブルを所有しマイグレーションを実行する。RLS は適用されない。
--   appstdio_app   : アプリが接続する。非スーパーユーザかつ非所有者なので RLS が適用される。
--
-- このファイルは postgres コンテナの初回起動時 (/docker-entrypoint-initdb.d) に実行される。
-- 既存のボリュームに対して手で流す場合も想定して冪等に書いている。

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'appstdio_owner') THEN
    -- db:create / db:test:prepare のために CREATEDB が必要
    CREATE ROLE appstdio_owner LOGIN PASSWORD 'owner_password' CREATEDB;
  END IF;

  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'appstdio_app') THEN
    -- NOSUPERUSER / NOBYPASSRLS / NOCREATEDB (CREATE ROLE の既定値)
    CREATE ROLE appstdio_app LOGIN PASSWORD 'app_password';
  END IF;
END
$$;

-- appstdio_app が RLS をすり抜けられないことを保証する
ALTER ROLE appstdio_app NOSUPERUSER NOBYPASSRLS NOCREATEDB NOCREATEROLE;

-- template1 に既定権限を仕込んでおくことで、この後 db:create で作られる
-- データベース (development / test) にもそのまま引き継がれる。
-- これが無いと、マイグレーションで作った新しいテーブルに appstdio_app が一切アクセスできない。
\connect template1

ALTER DEFAULT PRIVILEGES FOR ROLE appstdio_owner IN SCHEMA public
  GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO appstdio_app;

ALTER DEFAULT PRIVILEGES FOR ROLE appstdio_owner IN SCHEMA public
  GRANT USAGE, SELECT ON SEQUENCES TO appstdio_app;
