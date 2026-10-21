namespace :test do
  desc "運営者画面のテストを実行する（別ロール・別ルーティングのため独立したプロセスで動かす）"
  task :ops do
    sh({
      "OPS_CONSOLE" => "1",
      "DB_USER" => ENV.fetch("DB_OWNER_USER", "appstdio_owner"),
      "DB_PASSWORD" => ENV.fetch("DB_OWNER_PASSWORD", ""),
    }, "bin/rails test test/ops")
  end

  # Rails 本体の test:all と名前がぶつかると、bin/rails test:all では呼ばれず
  # 運営者画面側が skip のまま終わる
  desc "利用テナント側・運営者画面・E2E（Playwright）のテストをすべて実行する"
  task :full do
    sh "bin/rails test"
    Rake::Task["test:ops"].invoke
    sh "npx playwright test"
  end
end
