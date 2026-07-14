# frozen_string_literal: true

# SimpleCov configuration file, auto-loaded when the test helper starts
# coverage. Keep startup in test_helper.rb so this file remains configuration-only.

SimpleCov.configure do
  # Allow release/CI verification to use an isolated result set. Reusing a
  # developer's previous coverage directory can merge stale runs and hide a
  # regression that would fail in a clean checkout.
  coverage_dir ENV.fetch("COVERAGE_DIR", "coverage")

  # Use SimpleFormatter for terminal-only output (no HTML generation)
  formatter SimpleCov::Formatter::SimpleFormatter

  if respond_to?(:skip)
    # SimpleCov 1.x vocabulary.
    skip "/test/"
    cover "lib/**/*.rb"
  else
    # Fallback vocabulary for SimpleCov 0.22.
    add_filter "/test/"
    track_files "lib/**/*.rb"
  end

  # Enable branch coverage for more detailed metrics
  enable_coverage :branch

  # Set minimum coverage thresholds to prevent coverage regressions.
  minimum_coverage line: 80, branch: 75

  # Disambiguate parallel test runs
  command_name "Job #{ENV["TEST_ENV_NUMBER"]}" if ENV["TEST_ENV_NUMBER"]
end

# Print coverage summary to terminal after tests complete
SimpleCov.at_exit do
  SimpleCov.result.format!
  puts "\n" + "=" * 60
  puts "COVERAGE SUMMARY"
  puts "=" * 60
  puts "Line Coverage:   #{SimpleCov.result.covered_percent.round(2)}%"
  branch_coverage = SimpleCov.result.coverage_statistics[:branch]&.percent&.round(2) || "N/A"
  puts "Branch Coverage: #{branch_coverage}%"
  puts "=" * 60
end
