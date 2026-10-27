# 設計と実装方針

開発環境の動かし方は `docker/README.md` を参照。

設計の文書は次のように分けている。ここには全体に関わる決まりを置く。

| 文書 | 内容 |
|---|---|
| `doc/architecture.md`（この文書） | 用語、運営者画面、国際化、テスト、CI |
| `doc/database.md` | テナント分離（Row Level Security）、enum を持つ列の型 |
| `doc/frontend.md` | Vite / Vue.js、CSS（Tailwind CSS） |
| `doc/design.md` | 画面の見た目の決まり |
| `doc/files.md` / `doc/groups.md` | 機能ごとの仕様 |

## 用語

管理する立場のものが3つあるので、コード上の名前と画面の言葉を対応させておく。

| コード | 指すもの | 画面の言葉 |
|---|---|---|
| `operator`（`operators`、`/ops`、`Ops::`） | サービスの運営側。運営者画面を使う | 運営者 |
| `admin` / `owner`（`tenant_users.role`） | テナントの管理者。`/management` を使う | 管理者 / オーナー |
| `manager`（`files_permissions.role`） | ファイル・フォルダの管理権限 | 管理者 |

`admin` はテナントの管理者だけを指す。運営者を `admin` と呼ばない。
画面では「組織」と呼ぶものも、コードでは `tenant` と書く（「組織設定」は `TenantSetting`）。

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
| `config/locales/ja.files_app.yml` | ファイル画面（Vue）の文言。`doc/frontend.md` の「ファイル画面の構成」を参照 |

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
