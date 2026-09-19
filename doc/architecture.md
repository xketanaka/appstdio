# 設計と実装方針

開発環境の動かし方は `docker/README.md` を参照。

## テナント分離 (Row Level Security)

テナント間のデータ分離は PostgreSQL の RLS で行う。

### ロール構成

PostgreSQL は **スーパーユーザとテーブルの所有者には RLS を適用しない**。
そのため接続ロールを2つに分けている。定義は `docker/files/db/initdb/01_roles.sql`。

| ロール | 用途 | RLS |
|---|---|---|
| `appstdio_owner` | テーブルを所有する。マイグレーションとシステム管理画面が使う | 適用されない |
| `appstdio_app` | 利用テナント側のアプリが接続する（`DB_USER` の既定値） | **適用される** |

`appstdio_app` は非スーパーユーザかつ非所有者で、`BYPASSRLS` も持たない。
この前提が崩れると RLS は黙って素通りするため、`test/models/rls/rls_configuration_test.rb`
でロールの属性そのものをテストしている。

管理画面用に3つ目のロールを用意する案もあったが、採用しなかった。管理画面は全テナントを
扱うのが役割なので、専用ロールを作っても結局すべてを許可するポリシーを張ることになり、
所有者との差は DDL 権限の有無だけになる。ロールを1つ減らすほうが構成として単純。

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

## システム管理画面

管理画面は**同じコードベースを別プロセスとしてデプロイする**。プロセスが接続する
ロールと、配信するルーティングを環境変数で切り替える。

| | 公開側 | 管理側 |
|---|---|---|
| `DB_USER` | `appstdio_app` | `appstdio_owner` |
| `ADMIN_CONSOLE` | 未設定 | `1` |
| 配信する画面 | 利用テナント側のみ（`/admin` は 404） | `/admin` のみ（`/login` などは 404） |

**ルーティングを分けているのは必須の対策。** 管理側のプロセスで利用テナント側の画面を
配信すると、全クエリが所有者ロールで実行され、テナントを跨いだ遮断が効かなくなる。
逆に公開側で `/admin` を配信しても RLS で 0 件になり fail-closed だが、こちらも塞いでいる。

接続の切り替えはコードでは行わない。プロセスが持つ資格情報がそのままロールになるので、
`rails console` や `rails runner` で「どの接続か」を意識する必要はない。

Rails のシャード機構で1プロセス内に2接続を持つ構成も検討したが、採用しなかった。
接続の切り替えがコード上の概念になると、console や runner、ジョブのたびに
「いまどの接続か」を意識する必要が出る。しかも切り替え忘れの症状が例外ではなく
静かな 0 件で、最も気付きにくい形になる。

## CSS (Tailwind CSS)

`tailwindcss-rails` を使う。Node は不要で、スタンドアロンのバイナリでビルドする。
ビルドの操作は `docker/README.md` の「CSS のビルド」を参照。

### スタイルはすべてユーティリティで書く

独自の CSS ファイルは持たない。`app/assets/stylesheets/` は空で、スタイルはビューの
`class` 属性に直接書く。`@apply` でクラスを作るのは、Tailwind 側が推奨していないので
避ける。同じ組み合わせが増えてきたら、CSS ではなく partial かヘルパーにまとめる。

`@theme` で変更しているのはフォントスタックのみ（既定のスタックに日本語フォントが
含まれないため）。色は Tailwind 既定のパレット（slate / blue / green / amber / red）を
そのまま使っている。

### テストはスタイルのクラスを参照しない

`assert_select` は `id`、要素の構造、`role` 属性、テキストで書く。ユーティリティクラスは
見た目を変えるたびに変わるので、テストから参照すると壊れやすくなる。

flash の領域には `role="alert"` / `role="status"` が付いているので、そこを使う。

### Vue.js を導入する際は Vite に移す想定

`.vue`（単一ファイルコンポーネント）を使う場合はバンドラが必要になる。その際は
Tailwind も `@tailwindcss/vite` で処理して、ビルドの入口を1つにまとめる想定。

- `tailwindcss-rails` gem と `css` サービスを削除
- `app/assets/tailwind/application.css` を Vite のエントリへ移動
- `@tailwindcss/vite` を追加

現時点で `tailwindcss-rails` のままにしているのは、Vue の導入時期と SFC を使うかが
未定のため。Vite を先に入れても Vue が無いうちは構成を抱えるだけになる。
なお standalone バイナリでは**第三者製の Tailwind プラグインが使えない**
（第一者の typography / forms は使える）。これが必要になった時点でも移行の理由になる。
