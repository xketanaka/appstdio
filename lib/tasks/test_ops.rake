namespace :test do
  desc "管理画面のテストを実行する（別ロール・別ルーティングのため独立したプロセスで動かす）"
  task :ops do
    sh({
      "OPS_CONSOLE" => "1",
      "DB_USER" => ENV.fetch("DB_OWNER_USER", "appstdio_owner"),
      "DB_PASSWORD" => ENV.fetch("DB_OWNER_PASSWORD", ""),
    }, "bin/rails test test/ops")
  end

  # Rails 本体の test:all と名前がぶつかると、bin/rails test:all では呼ばれず
  # 管理画面側が skip のまま終わる
  desc "利用テナント側と管理画面の両方のテストを実行する"
  task :full do
    sh "bin/rails test"
    Rake::Task["test:ops"].invoke
  end
end
