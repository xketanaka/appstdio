# SimpleCov must be loaded before application code
require "simplecov"

SimpleCov.start "rails" do
  enable_coverage :branch

  # Exclude unnecessary files from coverage
  add_filter "/test/"
  add_filter "/config/"
  add_filter "/vendor/"

  # Coverage thresholds (optional)
  # minimum_coverage line: 80, branch: 70

  # Generate coverage report in HTML format
  formatter SimpleCov::Formatter::HTMLFormatter
end

ENV["RAILS_ENV"] ||= "test"
require_relative "../config/environment"
require "rails/test_help"
require "minitest/spec"
