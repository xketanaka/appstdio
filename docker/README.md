# docker 環境のセットアップ

## コンテナ構成

| サービス | 役割 | 主な環境変数 | 備考 |
|---|---|---|---|
| `app` | 利用テナント側のアプリ | `DB_USER=appstdio_app` | `/admin` は 404 |
| `admin` | システム管理画面 | `DB_USER=appstdio_owner`、`ADMIN_CONSOLE=1` | 利用テナント側の画面は 404 |
| `css` | Tailwind のビルド（ファイル監視） | - | `app` / `admin` とコードのボリュームを共有 |
| `db` | PostgreSQL 18 | - | 初回起動時に `docker/files/db/initdb/` を実行 |

`app` と `admin` は同じイメージ・同じコードで、環境変数だけが違う。なぜ分けているかは
`doc/architecture.md` の「システム管理画面」を参照。

## アクセスするためのポート設定

docker-compose.override.yml を配置する。必要であればホスト側のポート設定を変更する

```bash
cp docker/files/docker-compose.override.yml.example docker-compose.override.yml
```

## セットアップ

コンテナ作成,bundle install, rails serverを起動する

```bash
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
スキーマを変更する操作（`db:create` / `db:migrate` / `db:test:prepare` など）と、
RLS を迂回する必要がある操作（`db:seed`）は必ずこちらを使う。

通常の `bin/rails` はアプリ用ロールで接続するため、マイグレーションを実行しようとすると
`permission denied for table schema_migrations` で落ちる。これは意図した動作。
ロールを分けている理由は `doc/architecture.md` の「テナント分離」を参照。

以上でセットアップ完了。
ブラウザで docker-compose.override.yml で指定したポートにアクセスすると画面が表示される

## DB (PostgreSQL) への接続

```bash
# アプリと同じ条件（RLS が適用される）で確認したいとき
docker compose exec db psql -U appstdio_app -d appstdio_development

# スキーマを確認・変更したいとき、管理画面と同じ条件で見たいとき
docker compose exec db psql -U appstdio_owner -d appstdio_development
```

app コンテナにも psql / pg_dump (18系) が入っているので、そちらからでも接続できる

```bash
docker compose exec app psql -h db -U appstdio_app -d appstdio_development
```

rails console から管理側のデータを触る場合は所有者ロールで実行する

```bash
docker compose exec app bin/rails-as-owner console
```

## CSS のビルド

`css` サービスがファイルを監視して自動でビルドする。`docker compose up` に含まれている
ので通常は意識しなくてよい。

- 入力: `app/assets/tailwind/application.css`
- 出力: `app/assets/builds/tailwind.css`（git 管理外）

手で実行する場合は以下。

```bash
docker compose exec app bin/rails tailwindcss:build
```

**チェックアウト直後は出力ファイルが存在しない。** `docker compose up` すれば `css`
サービスが生成する。本番では `assets:precompile` に組み込まれている。

書き方の方針は `doc/architecture.md` の「CSS」を参照。

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
