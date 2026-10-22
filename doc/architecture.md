# 設計と実装方針

開発環境の動かし方は `docker/README.md` を参照。

## 用語

管理する立場のものが3つあるので、コード上の名前と画面の言葉を対応させておく。

| コード | 指すもの | 画面の言葉 |
|---|---|---|
| `operator`（`operators`、`/ops`、`Ops::`） | サービスの運営側。運営者画面を使う | 運営者 |
| `admin` / `owner`（`tenant_users.role`） | テナントの管理者。`/management` を使う | 管理者 / オーナー |
| `manager`（`files_permissions.role`） | ファイル・フォルダの管理権限 | 管理者 |

`admin` はテナントの管理者だけを指す。運営者を `admin` と呼ばない。
画面では「組織」と呼ぶものも、コードでは `tenant` と書く（「組織設定」は `TenantSetting`）。

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

## 運営者画面

運営者画面は**同じコードベースを別プロセスとしてデプロイする**。プロセスが接続する
ロールと、配信するルーティングを環境変数で切り替える。

| | 公開側 | 運営者画面側 |
|---|---|---|
| `DB_USER` | `appstdio_app` | `appstdio_owner` |
| `OPS_CONSOLE` | 未設定 | `1` |
| 配信する画面 | 利用テナント側のみ（`/ops` は 404） | `/ops` のみ（`/login` などは 404） |

**ルーティングを分けているのは必須の対策。** 運営者画面のプロセスで利用テナント側の画面を
配信すると、全クエリが所有者ロールで実行され、テナントを跨いだ遮断が効かなくなる。
逆に公開側で `/ops` を配信しても RLS で 0 件になり fail-closed だが、こちらも塞いでいる。

接続の切り替えはコードでは行わない。プロセスが持つ資格情報がそのままロールになるので、
`rails console` や `rails runner` で「どの接続か」を意識する必要はない。

Rails のシャード機構で1プロセス内に2接続を持つ構成も検討したが、採用しなかった。
接続の切り替えがコード上の概念になると、console や runner、ジョブのたびに
「いまどの接続か」を意識する必要が出る。しかも切り替え忘れの症状が例外ではなく
静かな 0 件で、最も気付きにくい形になる。

### 運営者のアカウント

運営者は `operators` に**利用者（`users`）とは別のアカウント**として持つ。
メールアドレスとパスワードも `operators` 自身が持ち、`users` とは紐付けない。

- 利用者側のログインは `users` しか見ないので、運営者は**仕組み上ログインできない**
- パスワードのハッシュは、利用者側の接続からは見えない `operators` にだけある

運営者と利用者を兼ねる人は、アカウントを2つ持つ。同じメールアドレスで両方に
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
| `config/locales/ja.files_app.yml` | ファイル画面（Vue）の文言。「ファイル画面の構成」を参照 |

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
- `test/views/hardcoded_text_test.rb` が `app/views/**/*.erb` と `app/javascript` の `.vue` / `.ts` を
  走査し、日本語の文字が残っていないことを検査する（コメントとテストのファイルは対象外）

なお rake タスクの `desc` や `db/seeds.rb` は開発者向けで画面に出ないため、対象外。

## CSS (Tailwind CSS)

Vite の中で `@tailwindcss/vite` を使ってビルドする（構成は「フロントエンド」を参照）。入口は
`app/javascript/entrypoints/application.css`。ビルドの操作は `docker/README.md` の
「フロントエンドのビルド」を参照。

Vite のルートは `app/javascript` なので、Tailwind がクラスを拾うのは既定ではその下だけになる。
ERB とヘルパーは `application.css` の `@source` で明示している。**クラスを書く場所を新しく
増やしたら `@source` にも足すこと。** 足し忘れると、そのクラスが黙って CSS に出力されない。

### スタイルは基本的にユーティリティで書く

独自の CSS ファイルは持たない。スタイルはビュー（ERB・Vue のテンプレート）の
`class` 属性に直接書く。同じ組み合わせが1つの側（ERB だけ、Vue だけ）で増えてきたら、
partial や Vue の部品にまとめる。

例外として、**ERB と Vue の両方で使う基本の部品**（ボタン・入力欄・左ペインの項目）だけは、
`application.css` の `@layer components` に部品のクラスとして置く（一覧は `doc/design.md` の「部品」）。
ヘルパーにまとめると Vue から使えず、ERB と Vue に同じクラスの並びを2つ持つことになるため。
CSS の層は ERB と Vue のどちらからも届く。

* `@apply` で何でもクラスにすると、CSS のファイルが育ってどれが使われているか分からなくなる。
  クラスにするのは上の部品だけに限る
* `@layer components` はユーティリティより下の層なので、`btn btn-primary w-full` のように
  足したユーティリティが必ず勝つ。`@layer` の外や `@utility` に置くと、この順序が崩れる

`@theme` で足しているのは、フォントスタック、ブランドカラー `primary`、画面の地の色 `canvas`、
見出しの文字サイズ `title`。何をどこに使うかは `doc/design.md` を参照。

フォントは Google Fonts の Noto Sans JP（ウェイト 400〜700）を使う。端末のフォント任せだと
Windows では游ゴシックやメイリオになり、OS ごとに見た目が変わるため。Google Fonts は文字の範囲
ごとにファイルを分けて配っており、画面で使う文字の分だけ読み込まれる。読み込めない環境では
`system-ui` などの端末のフォントで表示される。

- 読み込みの `<link>` は `layouts/application` と `layouts/ops` の両方にある
- CSP を有効にするときは `fonts.googleapis.com`（CSS）と `fonts.gstatic.com`（フォント）を許可する
- 外部へのアクセスを許さない環境に納めることになったら、フォントのファイルを自前で配る形に切り替える

### 見た目の決まり

色・文字・角丸・部品のクラス・画面の骨格（地とパネル）の決まりは `doc/design.md` にまとめてある。

### 開閉する UI は標準の要素で作る

ERB の画面では JavaScript のフレームワークを使わないため、開閉を伴う UI は HTML の標準要素で
組み立てる。`app/javascript/entrypoints/application.ts` が補うのは、標準では付いてこない動作だけ。

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

### 2ペインの画面

左ペインを持つ画面は `layouts/two_pane` を使う。枠（PC の左ペイン、スマホの折りたたみ、
右ペイン）はこのレイアウトにだけ書き、機能ごとに違うものを `content_for` で渡す。

| `content_for` | 内容 | 例 |
|---|---|---|
| `:pane_title` | 左ペインの先頭に出す機能名。スライドメニューの項目名 `menus.*` を使う | ファイル / 管理 |
| `:pane_summary` | スマホ幅の折りたたみの見出し | 今いる画面名 |
| `:pane` | 左ペインの中身。PC とスマホの2箇所に出るので、中に id を置かない | ツリー / 管理メニュー |
| `:banner` | 2ペインの上に全幅で出す帯（任意）。画面全体に関わる状態を示す | 特権モード中の表示 |

右ペインの見出しは開いている場所（「組織共有ドライブ」「利用者管理」）なので、
どの機能にいるかは左ペインの機能名で示す。

渡し方は、左ペインが複数の画面で共通かどうかで分ける。

- **1画面だけの機能**はビューで `content_for` を書き、コントローラで
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

ファイル画面は Vue.js のアプリなので、このレイアウトを使わず同じ枠を `app/javascript/files/App.vue` に
自分で描いている。**枠の見た目を変えるときは両方を直すこと。**

共通の partial を各ビューで `render layout:` として包む形は使わない。ブロックの中の
lazy lookup（`t(".heading")`）がビューではなく partial のキーを引いてしまう。

ログイン画面だけは中央寄せのカードのまま。未ログインの画面で、業務画面とは性質が違う。

画面の枠（ヘッダー・左ペイン・パネル）は `body` に直接並べず、`body` 直下の
`#app-shell`（`fixed inset-0 flex flex-col overflow-hidden`）の中に組む。ブラウザの拡張機能が
読み込み中に `body` へ要素を差し込むと、`body` の縦並びに加わって枠が押し縮められ、
パネルが消えた画面が一瞬見えていた（macOS の Chrome で報告。シークレットウィンドウでは起きない）。
固定した入れ物なら、大きさが画面だけで決まる。`fixed inset-0` は `100vh` と違い、スマホの
アドレスバーの分だけ画面からはみ出すこともない。

**`body` に直接、普通に並ぶ要素を足すと `#app-shell` の後ろに隠れて見えない。** 通知や
ダイアログを `body` の末尾に足すライブラリ（Vue の `Teleport to="body"` も同じ）を使うときは、
足し先を `#app-shell` の中にするか、`fixed` などで画面を基準に置く要素にすること。

### テストはスタイルのクラスを参照しない

`assert_select` は `id`、要素の構造、`role` 属性、テキストで書く。ユーティリティクラスは
見た目を変えるたびに変わるので、テストから参照すると壊れやすくなる。

flash の領域には `role="alert"` / `role="status"` が付いているので、そこを使う。

## フロントエンド（Vite / Vue.js）

JavaScript と CSS は Vite でビルドする（`vite_rails`）。画面の多くは ERB のままで、
画面の側に状態を多く持つものだけを Vue.js で作る。

| 項目 | 内容 |
|---|---|
| ソースの置き場所 | `app/javascript`（`config/vite.json` の `sourceCodeDir`）。`~/` で参照できる |
| 入口 | `app/javascript/entrypoints/`。ERB の画面は `application.ts` と `application.css` |
| 言語 | TypeScript。型の検査は `npm run typecheck`（`vue-tsc`） |
| テスト | Vitest + jsdom + Vue Test Utils。`*.test.ts` を部品の隣に置く。`npm test` |
| 書式の検査 | ESLint（`eslint.config.js`）。各推奨設定に、二重引用符・セミコロン無しなどの書式を足した緩めの設定。`npm run lint` / `npm run lint:fix` |
| 文言 | `config/locales` に置く（ERB と同じ）。Vue の画面へは入れ物のページで渡す |

TypeScript は 6 系に留めている。7 系（Go への移植版）は `vue-tsc` が使う内部の API を
公開しておらず、型の検査が動かないため。`vue-tsc` が対応したら上げる。

### Vue.js で作る画面の判断

どんな機能も ERB と少しの JavaScript で作れはするので、「作れるか」では分けない。
**画面の状態をどこに置くか**で分ける。次のどれかに当たる画面は Vue.js で作る。

* 保存する前の状態を画面がたくさん持つ。ただし、**1つのフォームの中で行を足し引きして
  まとめて送る程度なら ERB と少しの JavaScript で作る**（グループの編集のメンバー一覧など）。
  保存前の状態はフォームの入力値として持て、送ればサーバが同じ規則で確かめるので、画面の側に
  状態の置き場所を別に作らずに済む。フォームに収まらない状態（選択・開閉・並び順などが
  複数の区画にまたがる）を持つなら Vue.js にする
* 1つの操作で画面の多くの部分が連動する（選択に応じてツールバー・件数・各行が変わる）
* サーバを待たずに反応しなければならない操作が続く（ドラッグ、エディタへの入力）

今はファイル画面（`/files` 以下）が当たる。複数選択とドラッグ＆ドロップでの移動を
持つため。ヘッダは ERB のままで、その下を Vue.js のアプリにする。

* **1つの画面の中で ERB の部品と Vue.js を混ぜない。** 両方が同じ DOM を触ると、
  どちらが表示を持っているのかが分からなくなる
* Vue.js の画面のサーバ側は JSON を返す API になる。権限の判定は今までどおりサーバで
  行い、結果（閲覧できるか・編集できるか）を返す。判定の規則を JavaScript に持ち込まない
* API の応答の型は TypeScript 側に手で書く。Ruby 側には型の定義を置かない。
  食い違いが問題になってきたら、OpenAPI の定義を正としてテストと型の生成に使う形に移る

### ファイル画面の構成

```
GET /files/...（どの URL でも）  Files::AppController#show   入れ物のページ。ヘッダは ERB
  └ #files-app                  app/javascript/files         Vue のアプリ。URL から画面を決める（Vue Router）
      └ fetch /files/api/...    Files::Api::*Controller      JSON を返す。権限の判定はここ
```

* **URL は `config/routes.rb` と `app/javascript/files/router.ts` の2箇所に書く。** 直接開いたとき
  （再読み込み・ブックマーク）はサーバが受け、画面の中で移ったときは Vue Router が受ける。
  片方だけに足すと、画面の中では開けるのに再読み込みで 404 になる
* 入れ物のページは、フォルダが存在しなくても 200 を返す。見つからない旨は、API の 404 を
  受けて Vue が本文に出す
* API はログインが切れていても転送しない（401 を返す）。Vue はページを読み直し、
  ログイン画面への転送は入れ物のページに任せる
* 閲覧できない項目の付帯情報は、API の応答に含めない。画面で隠すだけでは応答を見れば分かる
* 文言は `config/locales/ja.files_app.yml`。`files_app` 以下をまるごと入れ物のページの
  `data-config` で渡し、`t("sections.trash")` のように引く（`app/javascript/files/i18n.ts`）。
  埋め込みは Rails と同じ `%{name}`。開発中とテストでは、無いキーは例外になる
* 画面をまたいで保つ状態（特権モード・左ペインの開閉・ツリー）は `store.ts` に置く。
  左ペインはスマホと PC の2箇所に描くので、開閉もここで揃える
* 作成・移動などで中身が変わったら `store.ts` の `changed()` を呼ぶ。`state.revision` が増え、
  開いている画面（`useLoad`）とツリーが読み直す。画面ごとに「どこを読み直すか」を書かずに済む
* ドラッグ＆ドロップは `dnd.ts`。ドラッグ中のものは `dataTransfer` ではなくモジュールの中に持つ
  （`dragover` の間は `dataTransfer` の中身を読めず、落とせるかを判定できないため）。
  他のアプリから持ち込まれたもの（ファイル）とは `dataTransfer` の種類で見分ける
* 左ペインのツリーは、最初はドライブ直下のフォルダだけを読み、深い階層は開いたときに
  `/files/api/tree/children` で読む。フォルダを開くと、そこまでの祖先を自動で開いてそのフォルダを
  選択中にする。作成・移動のあとは、読み込み済みの階層をまとめて読み直す
* テストは API を `test/integration/files_test.rb`、部品の表示を Vitest（文言は本物の
  `ja.files_app.yml` を読むのでキーの漏れも拾う）、主な流れを E2E で確かめる（「テスト」を参照）

### 開発サーバ

`vite` サービスが Vite の開発サーバを動かす。ブラウザはアセットを Rails から受け取り、
Rails がそれを `vite` サービスへ中継する（`VITE_RUBY_HOST=vite`）。変更の即時反映（HMR）の
WebSocket だけは Rails を通せない（Rails の中継は WebSocket を扱わない）ので、ブラウザから
`vite` サービスへつなぐ。リバースプロキシ越しに使うときは、プロキシで `/vite-dev/` を
`vite` サービスへ回し、`VITE_HMR_CLIENT_PORT` をプロキシのポートにする（`docker/README.md`）。

* Vite は既定で知らないホスト名からのアクセスを拒むので、`vite.config.ts` の
  `allowedHosts` に `vite` と `RAILS_DEVELOPMENT_HOSTS` を渡している
* vboxsf ではファイルの変更が通知されないので、Vite の監視はポーリング（1秒）にしている
* `node_modules` は Docker の名前付きボリュームに置く。npm が作るシンボリックリンクを
  vboxsf では作れないため。その代わり、ホスト側からは `node_modules` が見えない
* テストのときは、`vite_ruby` が初回にビルドする（`public/vite-test`）

開発サーバが動いていないとき（`vite` サービスを止めているときなど）は、`vite_ruby` が
要求のたびに変更を確かめてビルドし直す（`autoBuild`）。表示は遅くなるが画面は崩れない。

## テスト

### 層ごとの役割

基準は「**そのテストが、どの層までそろわないと確かめられないか**」。下の層で確かめられるものは
下の層で確かめ、上の層には持ち込まない。

| 層 | 確かめること | 置き場所 |
|---|---|---|
| モデル | 規則そのもの（権限の継承、同名の判定、作成時に権限と履歴を残すこと） | `test/models` |
| 結合 | サーバの約束事。401 / 403 / 404 の出し分け、API が返す中身、422 の文。ERB の画面は表示の中身まで（`assert_select`） | `test/integration` |
| 部品（Vitest） | Vue の部品が、与えたデータでどう描き、どう反応するか | `app/javascript/**/*.test.ts` |
| E2E（Playwright） | 利用者の主な流れを、実際の操作で端から端まで動かす | `test/e2e` |

**E2E は網羅しない。** 権限の組み合わせや入力の誤りの種類は、結合テストと Vitest で尽くす。
E2E は1つの操作につき主な流れを1本程度にする。遅く、落ちたときの原因も追いにくいため。

### E2E（Playwright）

Rails の system test（Capybara）ではなく、Playwright を TypeScript で使う。

* Capybara の system test はテストとサーバが DB の接続を共有し、トランザクションの巻き戻しで
  後片付けする。主な流れを動かすだけならその必要は無く、むしろ本番では起きない形で RLS の
  指定が消える（要求を並行して処理すると、先に終わった要求が `TenantContext.clear` する）
* ドラッグ＆ドロップ、修飾キー付きのクリックを本物の操作として起こせる（Selenium は苦手）

仕組み。

* テスト環境の Rails を、単体テストとは別の DB（`appstdio_e2e`、`DB_NAME` で切り替え）で起動する。
  DB は流し始める前に作り直し（`playwright.config.ts` の `webServer`）、後片付けはしない
* **テストのファイルごとに専用のテナントを作る**（`beforeAll` で `test/e2e/scenarios.rb` を
  `bin/rails e2e:scenario[名前]` 経由で呼ぶ）。RLS で他のテナントの行は見えないので、ファイル同士が
  データで干渉しない。ファイル同士は並行して流れ、1つのファイルのテストは1つのワーカーで順に流れる
* 同じファイルのテストはデータを共有する。データを変えるテストは、他のテストが見るものに
  触れないようにする。触れざるを得ないときは、そのテストだけ別のシナリオを呼ぶ
* 途中のテストが落ちると、Playwright はワーカーを作り直して残りを続け、`beforeAll` も
  もう一度動く。残りのテストは新しいテナントで流れる
* データは rake タスクで作るので、ファイルごとに Rails の起動の1〜2秒がかかる。遅さが問題に
  なったら、テスト環境だけの HTTP の入口に切り替える（本番で有効にならない守りが要る）
* ブラウザには外部のホスト名を引かせない。Google Fonts の応答が遅いと、ページの読み込みが
  終わらず落ちるため
* 開発用のコンテナでは、失敗時のトレースを `/tmp/e2e-results` に出す。vboxsf の上に zip を
  書くと壊れるため

## CI (GitHub Actions)

すべてのブランチへの push で `.github/workflows/ci.yml` が動く。ジョブは3つ。

| ジョブ | 内容 |
|---|---|
| `lint` | main 以外のブランチでは `rubocop --autocorrect` と `npm run lint:fix`（ESLint）で直せるものを直し、差分があれば `style: rubocop と ESLint の自動修正を当てる` としてそのブランチにコミットして push する。そのあと両方とも違反が残っていないかを確かめる |
| `frontend` | `npm run typecheck` で型を検査し、`npm test` で Vitest を実行する |
| `test` | PostgreSQL 18 のサービスに `docker/files/db/initdb/01_roles.sql` でロールを作り、所有者ロールでテスト用の DB を作り、`bin/vite build` でアセットをビルドし、Playwright のブラウザを入れてから `bin/rails test:full` を実行する。失敗したら E2E のレポートとトレースを成果物として残す |

注意すること。

* **自動修正のコミットが積まれたら、手元で pull してから作業を続ける。** そのまま次の
  コミットを push すると履歴が分かれて push が拒否される
* 自動修正は安全なもの（`--autocorrect`）だけ。意味が変わりうる修正（`--autocorrect-all`）は
  行わない。自動で直せない違反が残ればジョブが失敗する
* rubocop と ESLint の自動修正を1つのジョブにまとめているのは、別のジョブにすると両方が
  同じブランチへ push し、後から push した方が拒否されるため
* GitHub Actions が push したコミットでは、ワークフローは再び動かない。自動修正の
  コミットに対するテストは走らない（自動修正は書式の修正に限られるため）
* CI は Docker の開発環境ではなく、GitHub のランナーに直接 Ruby を入れて動かす。
  開発環境の `RUBYOPT=--parser=parse.y` は vboxsf 向けの対策なので、CI には入れていない
