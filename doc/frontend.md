# フロントエンドの設計

JavaScript・CSS のビルド（Vite）、Vue.js で作る画面、Tailwind CSS の書き方。画面の見た目の決まりは
`doc/design.md`、全体の方針と他の文書の一覧は `doc/architecture.md` を参照。

## Vite / Vue.js

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
  `ja.files_app.yml` を読むのでキーの漏れも拾う）、主な流れを E2E で確かめる（`doc/architecture.md` の「テスト」を参照）

### ファイルの保存（アップロード・ダウンロード）

ファイルの中身は Active Storage で保存する。保存先は最終的に S3 にするので、アップロードは
ダイレクトアップロード（ブラウザから保存先へ直接送る）にしてある。中身は Rails と nginx を通らない。

```
1. POST /files/api/nodes/prepare_upload   権限・大きさ・同名・容量を確かめ、blob と送り先の URL を作る
2. PUT  <送り先>                          ブラウザが中身を直接送る（開発ではディスク用の受け口）
3. POST /files/api/nodes/upload           中身の届いた blob をファイル（版1）として登録する
```

* 画面は `@rails/activestorage` の `DirectUpload` を使う（大きなファイルの MD5 を分けて計算する）。
  1段目の応答は、Active Storage 標準の受け口と同じ形にしてある
* **Active Storage 標準の受け口（`/rails/active_storage/direct_uploads`）は塞いである**
  （`config/routes.rb` の先頭）。ログインも権限も確かめずに保存先への書き込みを許すため
* 3段目でも、容量と同名を確かめ直す。1段目のあとに埋まりうるため。登録できなければ届いた中身を消す
* 容量は `files_settings.storage_used_bytes` に、上限を超えないときだけ足す1つの UPDATE で数える
* 送ったが登録まで進まなかった中身は、毎日 `Files::PurgeUnattachedBlobsJob` が消す（1日たったもの）
* ダウンロードは、閲覧権限を確かめてから、5分だけ有効な保存先の URL へ転送する
  （`files/api/nodes#download`）。Active Storage の公開ルートは使わない

S3 へ移すときに要ること。

* `config/storage.yml` に S3 を足し、`config.active_storage.service` を切り替える
* **バケットに CORS を設定する**（アプリのオリジンからの PUT と、`Content-Type` / `Content-MD5`
  などのヘッダを許す）。ブラウザから直接送るため
* ディスク保存のあいだは、中身を送る2段目が Rails（と前段の nginx）を通る。
  nginx の `client_max_body_size` を 5GB 以上にしておくこと

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

## CSS (Tailwind CSS)

Vite の中で `@tailwindcss/vite` を使ってビルドする（構成は「Vite / Vue.js」を参照）。入口は
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
