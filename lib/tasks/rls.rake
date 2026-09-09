namespace :db do
  desc "アプリ用ロールに DML 権限を付与する（所有者ロールで実行すること）"
  task grants: :environment do
    app_role = ENV.fetch("DB_APP_USER", "appstdio_app")

    ActiveRecord::Base.with_connection do |connection|
      role = connection.quote_column_name(app_role)

      # ALTER DEFAULT PRIVILEGES が無いと、以後追加するテーブルに権限が付かない
      connection.execute(<<~SQL)
        GRANT USAGE ON SCHEMA public TO #{role};
        GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public TO #{role};
        GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA public TO #{role};
        ALTER DEFAULT PRIVILEGES IN SCHEMA public
          GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO #{role};
        ALTER DEFAULT PRIVILEGES IN SCHEMA public
          GRANT USAGE, SELECT ON SEQUENCES TO #{role};
      SQL

      puts "#{connection.current_database}: #{app_role} に権限を付与しました"
    end
  end
end

Rake::Task["db:migrate"].enhance do
  Rake::Task["db:grants"].invoke
end
