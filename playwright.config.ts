import { defineConfig, devices } from "@playwright/test"

const port = 3100
// テスト環境の Rails を、単体テストとは別の DB（appstdio_e2e）で動かす
const env = { RAILS_ENV: "test", DB_NAME: "appstdio_e2e" }

export default defineConfig({
  testDir: "test/e2e",
  // 失敗時のトレース（zip）は vboxsf の上に書くと壊れるので、開発用のコンテナでは /tmp に出す
  outputDir: process.env.E2E_OUTPUT_DIR ?? "test-results",
  fullyParallel: true,
  forbidOnly: !!process.env.CI,
  reporter: process.env.CI ? [["list"], ["html", { open: "never" }]] : "list",
  use: {
    baseURL: `http://127.0.0.1:${port}`,
    locale: "ja-JP",
    timezoneId: "Asia/Tokyo",
    trace: "retain-on-failure",
  },
  projects: [{
    name: "chromium",
    use: {
      ...devices["Desktop Chrome"],
      launchOptions: {
        // 外部（Google Fonts など）へ取りに行かせない。届くのが遅いとページの読み込みが終わらない
        args: ["--host-resolver-rules=MAP * ~NOTFOUND, EXCLUDE 127.0.0.1, EXCLUDE localhost"],
      },
    },
  }],
  // 流し始める前に DB を作り直してからサーバを起動する。サーバが接続したあとでは DB を消せない。
  // pid のファイルを分けないと、同じコンテナで動いている開発用のサーバとぶつかる
  webServer: {
    command: `bin/rails-as-owner db:drop db:create db:schema:load && bin/rails server -p ${port} -b 127.0.0.1 -P tmp/pids/e2e.pid`,
    url: `http://127.0.0.1:${port}/up`,
    env,
    reuseExistingServer: false,
    timeout: 180_000,
  },
})
