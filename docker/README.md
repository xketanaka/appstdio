# docker 環境のセットアップ

## アクセスするためのポート設定

docker-compose.override.yml を配置する。必要であればホスト側のポート設定を変更する

```bash
cp docker/files/docker-compose.override.yml.example docker-compose.override.yml
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
bin/rails-as-owner db:seed
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
| `appstdio_owner` | テーブルを所有する。マイグレーションとシステム管理画面が使う | 適用されない |
| `appstdio_app` | 利用テナント側のアプリが接続する（`DB_USER` の既定値） | **適用される** |

`appstdio_app` は非スーパーユーザかつ非所有者で、`BYPASSRLS` も持たない。

管理画面用に3つ目のロールを用意する案もあったが、採用しなかった。管理画面は全テナントを
扱うのが役割なので、専用ロールを作っても結局すべてを許可するポリシーを張ることになり、
所有者との差は DDL 権限の有無だけになる。ロールを1つ減らすほうが構成として単純。
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
| `current_tenant_user` | 現在のテナントでの所属情報（表示名・権限・状態）。リクエストごとに解決される |
| `current_tenant` | 現在の `Tenant`（`current_tenant_user` から辿る） |
| `current_user` | ログイン中の `User`。**参照されたときにだけ読み込む** |

いずれもテナント未選択・未ログインなら `nil`。

`users` は認証情報しか持たず、通常の画面で必要になることはほとんどないため、
リクエストごとには読み込まない。所属情報はセッションの `current_user_id` と
`current_tenant_id` から `tenant_users` を直接引いて解決している。

ジョブ・コンソール・テストなど、リクエスト外から DB を触る場合は `TenantContext` を使う。

```ruby
TenantContext.switch(tenant: tenant, user: user) do
  TenantUser.count
end
```

### システム管理画面（別プロセス）

管理画面は**同じコードベースを別プロセスとしてデプロイする**。プロセスが接続する
ロールと、配信するルーティングを環境変数で切り替える。

| | 公開側 | 管理側 |
|---|---|---|
| `DB_USER` | `appstdio_app` | `appstdio_owner` |
| `ADMIN_CONSOLE` | 未設定 | `1` |
| 配信する画面 | 利用テナント側のみ（`/admin` は 404） | `/admin` のみ（`/login` などは 404） |

開発環境では `docker-compose.yml` の `app` と `admin` の2サービスが対応する。

**ルーティングを分けているのは必須の対策。** 管理側のプロセスで利用テナント側の画面を
配信すると、全クエリが所有者ロールで実行され、テナントを跨いだ遮断が効かなくなる。
逆に公開側で `/admin` を配信しても RLS で 0 件になり fail-closed だが、こちらも塞いでいる。

接続の切り替えはコードでは行わない。プロセスが持つ資格情報がそのままロールになるので、
`rails console` や `rails runner` で「どの接続か」を意識する必要はない。
開発環境で管理側のデータを触るときは所有者ロールで実行する。

```bash
docker compose exec app bin/rails-as-owner console
```

### 新しくテナントスコープのテーブルを追加するとき

`tenant_id` を持つテーブルには必ず RLS を有効にしてポリシーを張る。
書き方は `db/migrate/20260904220000_enable_row_level_security.rb` を参照。

- 更新系のポリシーには `WITH CHECK` を必ず付ける（無いと他テナントの行を作れてしまう）
- 適用先ロールを `TO appstdio_app` で明示する。省略すると `PUBLIC` 宛になり、
  ポリシーは permissive（OR 結合）なので、後から追加したロールにも適用されてしまう

どちらの付け忘れも `test/models/rls/rls_configuration_test.rb` が検出する。

`admin_users` は RLS を有効にしたうえで**ポリシーを1つも張っていない**。利用テナント側の
接続からは 0 件になり、所有者ロール（管理画面）は RLS を素通りするので参照できる。
`FORCE ROW LEVEL SECURITY` を付けると所有者にも適用されてしまうので付けないこと。

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

管理画面のテストは別ロール・別ルーティングのため、独立したプロセスで実行する。
`bin/rails test` では skip される。

```bash
docker compose exec app sh -c "bin/rails test:admin"   # 管理画面のみ
docker compose exec app sh -c "bin/rails test:all"     # 両方
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
