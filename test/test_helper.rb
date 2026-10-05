# SimpleCov must be loaded before application code
require "simplecov"

SimpleCov.start "rails" do
  enable_coverage :branch

  # Exclude unnecessary files from coverage
  skip "/test/"
  skip "/config/"
  skip "/vendor/"

  # Coverage thresholds (optional)
  # minimum_coverage line: 80, branch: 70

  # Generate coverage report in HTML format
  formatter SimpleCov::Formatter::HTMLFormatter
end

ENV["RAILS_ENV"] ||= "test"
require_relative "../config/environment"
require "rails/test_help"
require "minitest/spec"

module ActiveSupport
  class TestCase
    # describe を使うクラスでは test をすべて describe の中に書くこと。
    # describe より後に外側で定義した test はサブクラスにも継承され、重複して実行される
    extend Minitest::Spec::DSL
  end
end
