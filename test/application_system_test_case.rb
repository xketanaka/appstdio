require "test_helper"

class ApplicationSystemTestCase < ActionDispatch::SystemTestCase
  # テストとサーバは DB の接続を共有する。要求を並行して処理させると、先に終わった要求が
  # テナントの指定（RLS のセッション変数）を消し、もう一方の要求から行が見えなくなる
  Capybara.server = :puma, { Silent: true, Threads: "1:1" }

  # 開発用のコンテナ（arm64）では OS の Chromium を使う。CI では Selenium が Chrome を見つける
  driven_by :selenium, using: :headless_chrome, screen_size: [1280, 800] do |options|
    options.binary = "/usr/bin/chromium" if File.exist?("/usr/bin/chromium")
    options.add_argument("--no-sandbox")
    # 外部（Google Fonts など）へ取りに行かせない。届くのが遅いと、ページの読み込みが終わらず
    # visit が Net::ReadTimeout で落ちる。名前を引けなくすれば即座に失敗し、端末のフォントで描かれる
    options.add_argument("--host-resolver-rules=MAP * ~NOTFOUND, EXCLUDE 127.0.0.1, EXCLUDE localhost")
  end

  setup do
    Selenium::WebDriver::Chrome::Service.driver_path = "/usr/bin/chromedriver" if File.exist?("/usr/bin/chromedriver")
  end
end
