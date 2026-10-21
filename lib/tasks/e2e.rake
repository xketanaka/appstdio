namespace :e2e do
  desc "E2E テストのデータを1組作り、JSON で出力する（test/e2e から呼ぶ）"
  task :scenario, [:name] => :environment do |_task, args|
    abort "E2E のデータはテスト環境でしか作れません" unless Rails.env.test?

    require Rails.root.join("test/e2e/scenarios")
    puts E2eScenarios.public_send(args.fetch(:name)).to_json
  end
end
