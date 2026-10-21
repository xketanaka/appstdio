# docker 環境のセットアップ

## コンテナ構成

| サービス | 役割 | 主な環境変数 | 備考 |
|---|---|---|---|
| `app` | 利用テナント側のアプリ | `DB_USER=appstdio_app` | `/ops` は 404 |
| `ops` | 運営者画面 | `DB_USER=appstdio_owner`、`OPS_CONSOLE=1` | 利用テナント側の画面は 404 |
| `vite` | Vite の開発サーバ（JavaScript と CSS のビルド） | `VITE_LISTEN_PORT`（既定 3036） | `app` / `ops` とコードと `node_modules` のボリュームを共有 |
| `db` | PostgreSQL 18 | - | 初回起動時に `docker/files/db/initdb/` を実行 |

`app` と `ops` は同じイメージ・同じコードで、環境変数だけが違う。なぜ分けているかは
`doc/architecture.md` の「運営者画面」を参照。

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

# スキーマを確認・変更したいとき、運営者画面と同じ条件で見たいとき
docker compose exec db psql -U appstdio_owner -d appstdio_development
```

app コンテナにも psql / pg_dump (18系) が入っているので、そちらからでも接続できる

```bash
docker compose exec app psql -h db -U appstdio_app -d appstdio_development
```

rails console から運営者画面と同じ条件でデータを触る場合は所有者ロールで実行する

```bash
docker compose exec app bin/rails-as-owner console
```

## フロントエンドのビルド

`vite` サービスが Vite の開発サーバを動かし、JavaScript と CSS を変更に合わせて配る。
`docker compose up` に含まれているので通常は意識しなくてよい。起動のたびに `npm install` も行う。

- 入口: `app/javascript/entrypoints/`
- ポート: ホスト側の `VITE_LISTEN_PORT`（既定 3036）。変更の即時反映（HMR）の接続にブラウザが
  直接使う。**同じマシンで複数のチェックアウトを動かすときは `.env` で別の番号にする**
- 共有フォルダ（vboxsf）ではファイルの変更が通知されないため、1秒ごとのポーリングで監視している

手で実行するもの。

```bash
docker compose exec vite npm run typecheck   # 型の検査
docker compose exec vite npm test            # Vitest
docker compose exec vite npm run lint:fix    # ESLint（直せるものは直す）
docker compose exec vite bin/vite build      # 本番用のビルド（public/vite）
```

### リバースプロキシ越しに使う場合

ブラウザは HMR の WebSocket を「アドレスバーのホスト名」の `VITE_HMR_CLIENT_PORT` 番
（未設定なら `VITE_LISTEN_PORT`）へつなぐ。https のページからは `wss` になる。
リバースプロキシのポートだけを開けて使うときは、`.env` に

```
VITE_HMR_CLIENT_PORT=443
```

を書き、プロキシで `/vite-dev/` を `vite` サービスへ回す（WebSocket の切り替えを通す）。
nginx の例。

```nginx
# http ブロックに置く
map $http_upgrade $connection_upgrade {
  default upgrade;
  ''      close;
}

server {
  # ...（https の設定と、/ を app の 3000 番へ回す設定は今のまま）

  location /vite-dev/ {
    proxy_pass http://<VM のアドレス>:<VITE_LISTEN_PORT>;
    proxy_http_version 1.1;
    proxy_set_header Upgrade $http_upgrade;
    proxy_set_header Connection $connection_upgrade;
    proxy_set_header Host $host;
  }
}
```

* `Host` はブラウザが開いたホスト名のまま渡すこと。Vite は知らないホスト名を拒み、
  `RAILS_DEVELOPMENT_HOSTS` に書いたものだけを許している
* `/vite-dev/` は HTTP の要求もこの経路で `vite` サービスへ直接届く（Rails の中継を通らない）。
  どちらを通っても同じものが返る
* 繋がらなくても画面は動く。保存した変更の自動反映が効かず、手で再読み込みが要るだけ

**画面の CSS や JavaScript が読み込まれず、`/vite-dev/` が 502 になるとき**は、
`docker compose restart vite` で直る。Vite の導入前のブランチへ切り替えるなどで
`vite.config.ts` が一時的に無くなると、Vite が設定なしで再起動し、別のポートで待ち受けてしまう。

**npm のパッケージを足すときも `vite` コンテナの中で行う。** `node_modules` は Docker の
名前付きボリュームにあり、ホスト側からは見えない（vboxsf ではシンボリックリンクを作れないため）。

```bash
docker compose exec vite npm install --save-dev <パッケージ>
```

本番では `assets:precompile` に Vite のビルドが組み込まれている。

構成と書き方の方針は `doc/architecture.md` の「フロントエンド」と「CSS」を参照。

## テスト(Minitest)実行

すでにコンテナが起動している場合はアタッチして実行

```bash
docker compose exec app sh -c "bin/rails test"
```

運営者画面のテストは別ロール・別ルーティングのため、独立したプロセスで実行する。
`bin/rails test` では skip される。

```bash
docker compose exec app sh -c "bin/rails test:ops"     # 運営者画面のみ
docker compose exec app sh -c "bin/rails test:system"  # ブラウザを動かすテスト（system test）のみ
docker compose exec app sh -c "bin/rails test:full"    # すべて
```

system test はコンテナの Chromium（headless）で動く。失敗したときの画面は `tmp/screenshots/` に残る。

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
