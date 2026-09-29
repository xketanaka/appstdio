# 設計と実装方針

開発環境の動かし方は `docker/README.md` を参照。

## 用語

「管理者」に当たるものが3つあるので、コード上の名前で呼び分ける。

| コード | 指すもの | 画面の言葉 |
|---|---|---|
| `operator`（`operators`、`/ops`、`Ops::`） | サービスの運営側。システム管理画面を使う | システム管理者 |
| `admin` / `owner`（`tenant_users.role`） | テナントの管理者。`/management` を使う | 管理者 / オーナー |
| `manager`（`files_permissions.role`） | ファイル・フォルダの管理権限 | 管理者 |

`admin` はテナントの管理者だけを指す。システム管理者を `admin` と呼ばない。
画面では「組織」と呼ぶものも、コードでは `tenant` と書く。

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

`operators`（システム管理者）は RLS を有効にしたうえで**ポリシーを1つも張っていない**。利用テナント側の
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
寄せる場合は `MAX(role)` がそのまま書ける利点がある。現状 `Files::Permission.strongest`
は Ruby 側で配列の添字を見ており、この利点を使っていない。

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

## システム管理画面

管理画面は**同じコードベースを別プロセスとしてデプロイする**。プロセスが接続する
ロールと、配信するルーティングを環境変数で切り替える。

| | 公開側 | 管理側 |
|---|---|---|
| `DB_USER` | `appstdio_app` | `appstdio_owner` |
| `OPS_CONSOLE` | 未設定 | `1` |
| 配信する画面 | 利用テナント側のみ（`/ops` は 404） | `/ops` のみ（`/login` などは 404） |

**ルーティングを分けているのは必須の対策。** 管理側のプロセスで利用テナント側の画面を
配信すると、全クエリが所有者ロールで実行され、テナントを跨いだ遮断が効かなくなる。
逆に公開側で `/ops` を配信しても RLS で 0 件になり fail-closed だが、こちらも塞いでいる。

接続の切り替えはコードでは行わない。プロセスが持つ資格情報がそのままロールになるので、
`rails console` や `rails runner` で「どの接続か」を意識する必要はない。

Rails のシャード機構で1プロセス内に2接続を持つ構成も検討したが、採用しなかった。
接続の切り替えがコード上の概念になると、console や runner、ジョブのたびに
「いまどの接続か」を意識する必要が出る。しかも切り替え忘れの症状が例外ではなく
静かな 0 件で、最も気付きにくい形になる。

### システム管理者のアカウント

システム管理者は `operators` に**利用者（`users`）とは別のアカウント**として持つ。
メールアドレスとパスワードも `operators` 自身が持ち、`users` とは紐付けない。

- 利用者側のログインは `users` しか見ないので、システム管理者は**仕組み上ログインできない**
- パスワードのハッシュは、利用者側の接続からは見えない `operators` にだけある

システム管理者と利用者を兼ねる人は、アカウントを2つ持つ。同じメールアドレスで両方に
登録してよい。

## 国際化 (I18n)

将来の多言語対応に備えて、**文言はソースコードに直接書かない**。現時点の対応言語は
日本語のみ。

### 文言の置き場所

| ファイル | 内容 |
|---|---|
| `config/locales/ja.yml` | モデル名・属性名・enum の表示名 |
| `config/locales/ja.messages.yml` | flash や共通のメッセージ、ボタンのラベル (`actions`) |
| `config/locales/ja.views.yml` | ビューごとの文言。キーはビューのパスに対応 |

ビューでは lazy lookup を使う。`app/views/sessions/new.html.erb` の `t(".title")` は
`ja.sessions.new.title` を引く。レイアウトや partial でも同じで、
`app/views/partial/_paginate.html.erb` の `t(".next")` は `ja.partial.paginate.next`。

キーがビューのパスと1対1で対応するので、ビューを移動・削除したときに対応する
文言を見つけやすい。

各ビューには `title`（ブラウザのタイトル）と `heading`（`h1`）を必ず置く。同じ文字列に
なることが多いが、片方だけ変えたくなる場合に備えて分けている。

### 漏れを検出する仕組み

- `config.i18n.raise_on_missing_translations` を development / test で有効にしている。
  キーの指定漏れやタイポは「Translation missing」の表示ではなく例外になる
- `test/views/hardcoded_text_test.rb` が `app/views/**/*.erb` を走査し、日本語の文字が
  残っていないことを検査する（ERB のコメントは対象外）

なお rake タスクの `desc` や `db/seeds.rb` は開発者向けで画面に出ないため、対象外。

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

### 開閉する UI は標準の要素で作る

JavaScript のフレームワークを入れていないため、開閉を伴う UI は HTML の標準要素で
組み立てる。`app/javascript/application.js` が補うのは、標準では付いてこない動作だけ。

| UI | 要素 | JavaScript で補っている分 |
|---|---|---|
| アカウントのプルダウン | `details` / `summary` | 外側クリックと Esc で閉じる |
| 左のスライドメニュー | `dialog` (`showModal`) | 開閉と backdrop クリックで閉じる |

`dialog` の `showModal` を使うと backdrop、Esc での終了、フォーカスの閉じ込めが
標準で付く。プルダウンに `dialog` を使わないのは、top layer に上がるため CSS anchor
positioning 無しではボタンの位置に合わせられないため。

`dialog` にスライドのアニメーションを付ける際、修飾子の順序を間違えると**壊れた
セレクタが黙って生成される**。

```
backdrop:starting:open:opacity-0  ->  ::backdrop:is()   何にも一致しない
starting:open:backdrop:opacity-0  ->  :is([open])::backdrop
```

`open:` は `dialog` 自身の状態なので、`backdrop:` より先に書く。

### PC とスマホの両対応

Tailwind の既定のブレークポイントをそのまま使う（`sm` 40rem / `md` 48rem / `lg` 64rem）。
スマホを基準に書き、広い画面向けを修飾子で足す。

情報量が多い画面では、狭い幅で**列を隠して主要な列の下にまとめる**。消すのではなく
場所を変える。

```erb
<th class="hidden px-3 py-2.5 md:table-cell">更新日時</th>
...
<td class="px-3 py-2.5">
  <span>名前</span>
  <span class="mt-0.5 block text-xs text-slate-500 md:hidden">更新日時</span>
</td>
```

左ペインのように**配置ごと変わるもの**は、partial に切り出して2箇所から描画する。

```erb
<details class="md:hidden">...<%= render "tree" %></details>
<aside class="hidden md:block"><%= render "tree" %></aside>
```

`details` の `open` を CSS で制御できないため、1つの要素で「スマホでは折りたたみ、
PC では常に開く」を実現できない。`summary` を `md:hidden` で隠す手もあるが、
スマホ幅で閉じたままウィンドウを広げると開けなくなる。

### 画面全体を使うレイアウト

ヘッダより下は画面いっぱいに使う。カード（角丸・枠線・影で浮かせた箱）は使わず、
本文の器は左右の余白を持たない。Atlassian の Jira のような業務アプリの見た目に寄せている。

```
body      flex h-dvh flex-col overflow-hidden
header    shrink-0
本文の器   flex min-h-0 flex-1          余白も最大幅も持たない
ビュー     ここを自分で埋める
```

**ページ全体はスクロールしない。** `body` が `overflow-hidden` なので、
**各ビューが自分でスクロール領域を作る**。`min-h-0` を付け忘れると、flex の子が
内容の高さまで伸びてスクロールせずにはみ出すので注意。

ビューの書き方は2通り。

```erb
<%# 一覧など画面を埋めるもの。見出しは固定し、中身だけスクロールさせる %>
<div class="flex min-h-0 flex-1 flex-col">
  <div class="shrink-0 px-4 py-3">見出し</div>
  <div class="min-h-0 flex-1 overflow-auto px-4">一覧</div>
</div>

<%# フォームや詳細。読みやすさのため最大幅を設ける %>
<div class="min-h-0 flex-1 overflow-y-auto">
  <div class="mx-auto w-full max-w-3xl px-4 py-6 sm:px-6 sm:py-8">本文</div>
</div>
```

一覧の表は左右に 16px（`px-4`）の余白を取り、ペインの端まで広げない。端まで届くと
表が枠に貼り付いて見えるため（GitHub のファイル一覧程度の余白）。見出しの行も
同じ `px-4` にして、見出しと表の左端をそろえる。

見出しの行には下線を引かない。区切りは表の見出し行の線だけにする（Google ドライブと同じ）。
見出しの行に左右いっぱいの線を引くと、その直下にある内側に寄せた表の線と長さが食い違う。

表の絞り込み（キーワード・状態など）を置くときは、見出しの行には入れず、見出しと表の間に
専用の行を設ける。見出しの行は「今いる場所と、そこへの操作（作成など）」、絞り込みの行は
「表の見え方を変える操作」と役割を分ける。この行もスクロールさせず（`shrink-0`）、
左右は `px-4`。

### 2ペインの画面

左ペインを持つ画面は `layouts/two_pane` を使う。枠（PC の左ペイン、スマホの折りたたみ、
右ペイン）はこのレイアウトにだけ書き、機能ごとに違うものを `content_for` で渡す。

| `content_for` | 内容 | 例 |
|---|---|---|
| `:pane_title` | 左ペインの先頭に出す機能名。スライドメニューの項目名 `menus.*` を使う | ファイル / 管理 |
| `:pane_summary` | スマホ幅の折りたたみの見出し | ドライブ / 今いる画面名 |
| `:pane` | 左ペインの中身。PC とスマホの2箇所に出るので、中に id を置かない | ツリー / 管理メニュー |

右ペインの見出しは開いている場所（「組織共有ドライブ」「利用者管理」）なので、
どの機能にいるかは左ペインの機能名で示す。

渡し方は、左ペインが複数の画面で共通かどうかで分ける。

- **1画面だけの機能**（ファイル）はビューで `content_for` を書き、コントローラで
  `layout "two_pane"` を指定する
- **複数のコントローラで左ペインが共通の機能**（管理）は、`content_for` だけを書いた
  機能別のレイアウトを作り、最後に `render template: "layouts/two_pane"` する。
  レイアウトは `management → two_pane → application` と入れ子になる

```erb
<%# layouts/management.html.erb %>
<% content_for :pane_title, t("menus.management") %>
<% content_for :pane_summary, t("management.menu.items.#{controller_name}") %>
<% content_for :pane do %><%= render "management/menu" %><% end %>
<%= render template: "layouts/two_pane" %>
```

共通の partial を各ビューで `render layout:` として包む形は使わない。ブロックの中の
lazy lookup（`t(".heading")`）がビューではなく partial のキーを引いてしまう。

ログイン画面だけは中央寄せのカードのまま。未ログインの画面で、業務画面とは性質が違う。

`h-screen` ではなく `h-dvh` を使っている。スマホでアドレスバーの分だけ `100vh` が
画面からはみ出すため。

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
