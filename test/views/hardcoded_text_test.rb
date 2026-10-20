require "test_helper"

class HardcodedTextTest < ActiveSupport::TestCase
  JAPANESE = /[ぁ-んァ-ヶ一-龠]/

  test "ビューに文言が直接書かれていない" do
    offenders = offenders_in(Dir[Rails.root.join("app/views/**/*.erb")]) { |source| source.gsub(/<%#.*?%>/m, "") }

    assert_empty offenders,
      "ビューに文言が直接書かれています。config/locales へ移して t(\".key\") で引いてください"
  end

  test "Vue の画面に文言が直接書かれていない" do
    paths = Dir[Rails.root.join("app/javascript/**/*.{vue,ts}")].reject { |path| path.match?(/\.test\.ts\z|testing\.ts\z/) }
    offenders = offenders_in(paths) do |source|
      source.gsub(/<!--.*?-->/m, "").gsub(%r{/\*.*?\*/}m, "").gsub(%r{//.*$}, "")
    end

    assert_empty offenders,
      "Vue の画面に文言が直接書かれています。config/locales/ja.files_app.yml へ移して t(\"key\") で引いてください"
  end

  private

  def offenders_in(paths)
    paths.sort.filter_map do |path|
      source = yield File.read(path)
      numbers = source.lines.each_with_index.filter_map { |line, i| i + 1 if line.match?(JAPANESE) }
      next if numbers.empty?

      "#{path.delete_prefix("#{Rails.root}/")}:#{numbers.join(",")}"
    end
  end
end
