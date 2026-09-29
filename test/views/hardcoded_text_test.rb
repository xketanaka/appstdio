require "test_helper"

class HardcodedTextTest < ActiveSupport::TestCase
  JAPANESE = /[ぁ-んァ-ヶ一-龠]/

  test "ビューに文言が直接書かれていない" do
    offenders = Dir[Rails.root.join("app/views/**/*.erb")].sort.filter_map do |path|
      source = File.read(path).gsub(/<%#.*?%>/m, "")
      numbers = source.lines.each_with_index.filter_map { |line, i| i + 1 if line.match?(JAPANESE) }
      next if numbers.empty?

      "#{path.delete_prefix("#{Rails.root}/")}:#{numbers.join(",")}"
    end

    assert_empty offenders,
      "ビューに文言が直接書かれています。config/locales へ移して t(\".key\") で引いてください"
  end
end
