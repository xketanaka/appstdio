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

bundle exec rake db:create
RAILS_ENV=development bundle exec rake db:migrate
RAILS_ENV=development bundle exec rake db:seed
RAILS_ENV=test bundle exec rake db:migrate
RAILS_ENV=test bundle exec rake db:seed
```

以上でセットアップ完了。
ブラウザで docker-compose.override.yml で指定したポートにアクセスすると画面が表示される

## DB (PostgreSQL) への接続

DB は PostgreSQL 18。psql で接続する場合は db コンテナから実行する

```bash
docker compose exec db psql -U postgres -d appstdio_development
```

app コンテナにも psql / pg_dump (18系) が入っているので、そちらからでも接続できる

```bash
docker compose exec app psql -h db -U postgres -d appstdio_development
```

### RLS (Row Level Security) について

マルチテナントの分離に RLS を使う予定だが、PostgreSQL では **スーパーユーザとテーブル所有者に RLS が適用されない**。
現状の接続ロールは superuser の `postgres` なので、RLS を導入する際は

- マイグレーション用の所有者ロール
- アプリ接続用の非スーパーユーザロール (こちらに RLS が適用される)

を分けるか、テーブルに `FORCE ROW LEVEL SECURITY` を付ける必要がある。

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
