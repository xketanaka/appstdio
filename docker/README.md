# docker 環境のセットアップ

## アクセスするためのポート設定

docker-compose.override.yml を配置する。必要であればホスト側のポート設定を変更する

```bash
cd docker/
cp files/docker-compose.override.yml.example docker-compose.override.yml
```

## セットアップ

コンテナ作成,bundle install, rails serverを起動する

```bash
cd docker/
docker compose up -d
```

## DBのセットアップ

起動しているコンテナにアタッチする

```bash
docker compose exec app bash
```

以下のコマンドをコンテナ内で実行する

```bash
# In container

bin/rails-as-owner db:create
bin/rails-as-owner db:migrate
bin/rails db:seed
bin/rails-as-owner db:test:prepare
```

`bin/rails-as-owner` は所有者ロールに切り替えて `bin/rails` を実行するラッパー。
スキーマを変更する操作（`db:create` / `db:migrate` / `db:test:prepare` など）は
必ずこちらを使う。理由は後述の「RLS について」を参照。

通常の `bin/rails` はアプリ用ロールで接続するため、マイグレーションを実行しようとすると
`permission denied for table schema_migrations` で落ちる。これは意図した動作。

以上でセットアップ完了。
ブラウザで docker-compose.override.yml で指定したポートにアクセスすると画面が表示される

## DB (PostgreSQL) への接続

DB は PostgreSQL 18。psql で接続する場合は db コンテナから実行する

```bash
# アプリと同じ条件（RLS が適用される）で確認したいとき
docker compose exec db psql -U appstdio_app -d appstdio_development

# スキーマを確認・変更したいとき
docker compose exec db psql -U appstdio_owner -d appstdio_development
```

app コンテナにも psql / pg_dump (18系) が入っているので、そちらからでも接続できる

```bash
docker compose exec app psql -h db -U appstdio_app -d appstdio_development
```

## RLS (Row Level Security) について

テナント間のデータ分離は PostgreSQL の RLS で行う。

### ロール構成

PostgreSQL は **スーパーユーザとテーブルの所有者には RLS を適用しない**。
そのため接続ロールを2つに分けている。定義は `docker/files/db/initdb/01_roles.sql`。

| ロール | 用途 | RLS |
|---|---|---|
| `appstdio_owner` | テーブルを所有し、マイグレーションを実行する | 適用されない |
| `appstdio_app` | アプリが接続する（`database.yml` の既定値） | **適用される** |

`appstdio_app` は非スーパーユーザかつ非所有者で、`BYPASSRLS` も持たない。
この前提が崩れると RLS は黙って素通りするため、`test/models/rls/rls_configuration_test.rb`
でロールの属性そのものをテストしている。

ロールは postgres コンテナの初回起動時（ボリュームが空のとき）に自動で作られる。
既存のボリュームに対して後から適用する場合は、上記 SQL を手で流す。

### テナントコンテキストの受け渡し

ポリシーは PostgreSQL のセッション変数を参照する。

| 変数 | 内容 |
|---|---|
| `app.tenant_id` | 現在操作しているテナント |
| `app.user_id` | 現在ログインしているユーザ |

未設定なら `current_setting(..., true)` が NULL を返して1行も一致しないため、
**設定漏れは「他テナントが見える」ではなく「0件」になる**（fail-closed）。

Web リクエストでは `TenantContextFilter`（`ApplicationController` に include 済み）が
自動で設定・解除するので、コントローラ側で意識する必要はない。

解決した結果はコントローラのインスタンス変数に入る。参照は `SessionsHelper` の
アクセサを使う（コントローラ・ビューのどちらからでも呼べる）。

| メソッド | 内容 |
|---|---|
| `current_user` | ログイン中の `User`（`users` は認証情報のみ） |
| `current_tenant_user` | 現在のテナントでの所属情報（表示名・権限・状態） |
| `current_tenant` | 現在の `Tenant`（`current_tenant_user` から辿る） |

いずれもテナント未選択・未ログインなら `nil`。

ジョブ・コンソール・テストなど、リクエスト外から DB を触る場合は `TenantContext` を使う。

```ruby
TenantContext.switch(tenant: tenant, user: user) do
  TenantUser.count
end
```

### 新しくテナントスコープのテーブルを追加するとき

`tenant_id` を持つテーブルには必ず RLS を有効にしてポリシーを張る。
書き方は `db/migrate/20260904220000_enable_row_level_security.rb` を参照。

- 更新系のポリシーには `WITH CHECK` を必ず付ける（無いと他テナントの行を作れてしまう）
- 適用先ロールを `TO appstdio_app` で明示する。省略すると `PUBLIC` 宛になり、
  ポリシーは permissive（OR 結合）なので、後から追加したロールにも適用されてしまう

どちらの付け忘れも `test/models/rls/rls_configuration_test.rb` が検出する。

なお `tenants` と `users` には RLS を掛けていない。
どちらもテナントコンテキストを確定させる**前に**参照する必要があるテーブルのため
（ログイン時の `users` 検索、所属テナントの解決）。

### スキーマの管理形式

RLS のポリシーは `schema.rb`（Ruby形式）では表現できないため、
`config.active_record.schema_format = :sql` にして `db/structure.sql` を使っている。
`schema.rb` に戻すとポリシーが `db:schema:load` / `db:test:prepare` で失われる。

### RLS が守るもの・守らないもの

RLS が防げるのは **アプリケーションのバグ**（`where tenant_id = ?` の書き忘れなど）による
テナント跨ぎの漏洩。

一方、任意の SQL を実行できる状態（SQLインジェクションなど）に対しては防御にならない。
攻撃者自身が `set_config('app.tenant_id', ...)` を呼べてしまうため。
そちらは通常どおりアプリケーション側で防ぐ必要がある。

## テスト(Minitest)実行

すでにコンテナが起動している場合はアタッチして実行

```bash
docker compose exec app sh -c "bin/rails test"
```

コンテナが起動してない場合

```bash
docker compose run --rm app sh -c "bin/rails test"
```

## ブラウザテスト実行 (将来追加予定。現時点ではまだない)

### A.一括実行

app と browser_test を一括で実行する（docker compose up していない状態で実行）

```bash
cd docker/
docker compose -f docker-compose.browser_test.yml up
```

### B.個別実行

app と browser_test を別々に実行する（テストの開発中にオススメ）

docker compose up していない状態から、COMMANDを指定してコンテナを起動する

```
cd docker/
COMMAND=browser_test:run_server docker compose up -d
```

起動した状態で browser_test コンテナにアタッチする

```bash
docker compose exec browser_test bash
```

コンテナ内で以下を実行する。２回目以降の実行では `npm run clean-setup` は不要

```bash
# In browser_test container

npm run clean-setup
npm test

## [SUCCESS!] と表示されたらCtrl-Cで終了する
```
