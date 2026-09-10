namespace :test do
  desc "管理画面のテストを実行する（別ロール・別ルーティングのため独立したプロセスで動かす）"
  task :admin do
    sh({
      "ADMIN_CONSOLE" => "1",
      "DB_USER" => ENV.fetch("DB_OWNER_USER", "appstdio_owner"),
      "DB_PASSWORD" => ENV.fetch("DB_OWNER_PASSWORD", ""),
    }, "bin/rails test test/admin")
  end

  desc "利用テナント側と管理画面の両方のテストを実行する"
  task :all do
    sh "bin/rails test"
    Rake::Task["test:admin"].invoke
  end
end
