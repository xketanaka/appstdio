# データベースの設計

テナント分離（Row Level Security）と、列の型の決まり。全体の方針と他の文書の一覧は
`doc/architecture.md` を参照。

## テナント分離 (Row Level Security)

テナント間のデータ分離は PostgreSQL の RLS で行う。

### ロール構成

PostgreSQL は **スーパーユーザとテーブルの所有者には RLS を適用しない**。
そのため接続ロールを2つに分けている。定義は `docker/files/db/initdb/01_roles.sql`。

| ロール | 用途 | RLS |
|---|---|---|
| `appstdio_owner` | テーブルを所有する。マイグレーションと運営者画面が使う | 適用されない |
| `appstdio_app` | 利用テナント側のアプリが接続する（`DB_USER` の既定値） | **適用される** |

`appstdio_app` は非スーパーユーザかつ非所有者で、`BYPASSRLS` も持たない。
この前提が崩れると RLS は黙って素通りするため、`test/models/rls/rls_configuration_test.rb`
でロールの属性そのものをテストしている。

運営者画面用に3つ目のロールを用意する案もあったが、採用しなかった。運営者画面は全テナントを
扱うのが役割なので、専用ロールを作っても結局すべてを許可するポリシーを張ることになり、
所有者との差は DDL 権限の有無だけになる。ロールを1つ減らすほうが構成として単純。

### テナントコンテキストの受け渡し

ポリシーは PostgreSQL のセッション変数を参照する。

| 変数 | 内容 |
|---|---|
| `app.tenant_id` | 現在操作しているテナント |
| `app.user_id` | 現在ログインしているユーザ。テナントをまたいで自分の所属を引くとき（`own_memberships()`）にだけ使う |

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

### テナントをまたいで引くのはテナントの選択だけ

`tenant_users` を含め、どのテーブルのポリシーも `app.tenant_id` の行しか見せない。ただしテナントの
選択の画面では、自分が所属するテナントの一覧（他のテナントの自分の行）が要る。これは
所有者の権限で動く関数 `own_memberships()`（`SECURITY DEFINER`）から引き、`TenantUser.own_memberships`
として使う。返すのは `app.user_id` の行だけで、未設定なら0件。読み取り専用にしてある。

以前は `tenant_users` の SELECT のポリシーに `user_id = app.user_id` の OR を付けていたが、
普段の `TenantUser` の問い合わせに、管理者自身の他のテナントでの所属が混ざっていた
（利用者管理の一覧に1行出ていた）。テナントをまたぐ入口をこの関数1つに限り、検索すれば
見つかるようにした。ビューにしなかったのは、ビューは既定の権限付与で `appstdio_app` に
書き込み権限まで付き、単純なビューは更新できるので、所有者の権限で RLS を通らずに
書き換えられてしまうため（権限の付与・取り消しは `structure.sql` に残らず、取り消しで守れない）。

リクエストでは `TenantContextFilter` が、セッションのテナントを先に `app.tenant_id` に設定してから
自分の所属行を探し、見つからなければ（所属していない・有効でない）テナントの設定を外す。

`users` は認証情報しか持たず、通常の画面で必要になることはほとんどないため、
リクエストごとには読み込まない。所属情報はセッションの `current_user_id` と
`current_tenant_id` から `tenant_users` を直接引いて解決している。

ジョブ・コンソール・テストなど、リクエスト外から DB を触る場合は `TenantContext` を使う。

```ruby
TenantContext.switch(tenant: tenant, user: user) do
  TenantUser.count
end
```

### 所属の有効性は入口でだけ判定する

`tenant_users.status` を見るのは `TenantContextFilter` とテナント選択の2箇所だけ。
`current_tenant_user` が存在する時点でその所属は `active` なので、**個別機能の中で
status を再確認しない**。

この前提は `test/integration/login_flow_test.rb` と
`test/controllers/tenant_context_filter_test.rb` で担保している。

将来ジョブなどで「ユーザの代理で動く」処理を追加するときは、そこにも同じ判定が要る。

### 新しくテナントスコープのテーブルを追加するとき

`tenant_id` を持つテーブルには必ず RLS を有効にしてポリシーを張る。
書き方は `db/migrate/20260904220000_enable_row_level_security.rb` を参照。

- 更新系のポリシーには `WITH CHECK` を必ず付ける（無いと他テナントの行を作れてしまう）
- 適用先ロールを `TO appstdio_app` で明示する。省略すると `PUBLIC` 宛になり、
  ポリシーは permissive（OR 結合）なので、後から追加したロールにも適用されてしまう

どちらの付け忘れも `test/models/rls/rls_configuration_test.rb` が検出する。

`operators`（運営者）は RLS を有効にしたうえで**ポリシーを1つも張っていない**。利用テナント側の
接続からは 0 件になり、所有者ロール（運営者画面）は RLS を素通りするので参照できる。
`FORCE ROW LEVEL SECURITY` を付けると所有者にも適用されてしまうので付けないこと。

なお `tenants` と `users` には RLS を掛けていない。
どちらもテナントコンテキストを確定させる**前に**参照する必要があるテーブルのため
（ログイン時の `users` 検索、所属テナントの解決）。

そのため、テナントごとの設定は `tenants` に列を足さず、`tenant_id` を持つ別テーブル
（組織設定は `tenant_settings`、ファイル機能は `files_settings`）に置いて RLS で守る。
利用者側の画面から RLS の無い `tenants` を更新させると、アプリのバグで他テナントの行を
書き換えられる。主キーが uuid の `tenants` には Active Storage の添付（ポリモーフィック
関連）を付けられない、という理由もある。

Active Storage のテーブルは `tenant_id` を持たないので RLS を掛けていない。blob への
到達は推測できない署名付き ID に頼る。ロゴのように誰に見られてもよいものはそれでよいが、
権限の判定が要るダウンロード（ファイル機能）は、公開ルート（`/rails/active_storage/...`）
に直接つなげず、権限を判定するコントローラを通すこと。

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

## enum を持つ列の型

`status` / `role` / `kind` / `action` のような列は、**varchar + CHECK 制約**で持っている。
Rails の `enum` は列の型を選ばないので、integer でも varchar でも動く。

varchar にしている理由は2つ。

* **CHECK 制約で値の集合ごと縛れる。** `CHECK (role IN ('viewer','editor','manager','none'))`
  は意味まで書かれるが、integer の `CHECK (role IN (0,1,2,3))` は個数しか縛れない。
  `structure.sql` をリポジトリに入れており、RLS のポリシーも SQL で書くため、
  スキーマが自己記述であることの価値が大きい
* **integer は並べ替えが静かに事故る。** `enum :status, [:active, :suspended]` の順序を
  入れ替えると、マイグレーションも警告も無く既存レコードの意味が反転する

### PostgreSQL の ENUM 型に移す選択肢

性能を詰めたくなったときの選択肢として有効で、**大きな欠点は無い**。

| | varchar + CHECK | PG ENUM |
|---|---|---|
| 容量 | 値の長さ分 | 4バイト |
| 順序比較 | `CASE` が必要 | 宣言順でそのまま比較できる |
| SQL から読める | ○ | ○ |

とくに**段階に意味がある列**（`files_permissions.role` など）で、権限の解決を SQL 側に
寄せる場合は `MAX(role)` がそのまま書ける利点がある。現状の `Files::Access` は
varchar のまま、`array_position` で順位に置き換えてから `max` を取っている。

移すときに知っておくこと（実測で確認済み）。

* **値の追加・改名はできる。** `ALTER TYPE ... ADD VALUE 'x' BEFORE 'y'`（並び順も指定可）、
  `ALTER TYPE ... RENAME VALUE 'a' TO 'b'`
* **値の削除だけコマンドが無い。** 型を作り直して `ALTER COLUMN ... TYPE` で移す。
  これは**テーブル全体の書き換え**になり、その間 `ACCESS EXCLUSIVE` ロックを取る。
  20万行で 177ms だったので、行数に比例して見積もればよい。`DEFAULT` を先に外さないと
  `default for column cannot be cast automatically` で落ちる
* **追加した値を同じトランザクション内で使えない**（`unsafe use of new value`）。
  Rails のマイグレーションは既定でトランザクションなので、値の追加と既存データの移行を
  1本のマイグレーションに書けない。`disable_ddl_transaction!` を付けるか2本に分ける

列ごとに性質で選べばよく、全列を揃える必要はない。値が安定していて順序に意味がある列は
PG ENUM 向き、値が増減しそうで行数が伸びる列（`files_activities.action` など）は
varchar 向き。

実際に PG ENUM にしているのは `files_nodes.kind`（`folder` / `file`）。値を削除する場面が
来ないため、PG ENUM の唯一の欠点が当たらない。なお容量は理由にならない。実測では
30万行で varchar との差は 1% で、行が uuid・bigint・timestamp 中心だと
アラインメントの詰め物に吸収される。

`kind` を `boolean` にしなかったのは、ショートカットのような3つ目の種別が来る可能性が
あるため。boolean だと列の追加だけでなく既存のクエリをすべて書き換えることになる。

`enum ..., validate: true` を付けている列は、未知の値を**代入時には弾かない**。
バリデーションで不正にする仕様なので、DB 側の型や CHECK と二段構えになる。
