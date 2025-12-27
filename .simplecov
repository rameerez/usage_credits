# frozen_string_literal: true

SimpleCov.start 'rails' do
  # Coverage directory
  coverage_dir 'coverage'

  # Enable branch coverage (must be before minimum_coverage)
  enable_coverage :branch

  # Set minimum coverage threshold to prevent coverage regression
  # Current coverage: Line 84.38%, Branch 71.9%
  # Note: Some paths (PostgreSQL JSON operators, error fallbacks) may not be exercised in SQLite tests
  minimum_coverage line: 75, branch: 60

  # Add custom groups for better organization
  add_group 'Models', 'lib/usage_credits/models'
  add_group 'Services', 'lib/usage_credits/services'
  add_group 'Helpers', 'lib/usage_credits/helpers'
  add_group 'Jobs', 'lib/usage_credits/jobs'
  add_group 'Concerns', 'lib/usage_credits/models/concerns'
  add_group 'DSL', ['lib/usage_credits/operation.rb', 'lib/usage_credits/credit_pack.rb', 'lib/usage_credits/credit_subscription_plan.rb']

  # Filter out files we don't want to track
  add_filter '/test/'
  add_filter '/spec/'
  add_filter '/config/'
  add_filter '/db/'
  add_filter '/vendor/'
  add_filter '/bin/'

  # Track all Ruby files in lib
  track_files 'lib/**/*.rb'

  # Disambiguate parallel test runs
  command_name "Job #{ENV['TEST_ENV_NUMBER']}" if ENV['TEST_ENV_NUMBER']

  # Use different formatters for CI vs local
  if ENV['CI']
    # CI: Use simple formatter for console output
    formatter SimpleCov::Formatter::SimpleFormatter
  else
    # Local: Use HTML formatter for detailed report
    formatter SimpleCov::Formatter::HTMLFormatter
  end

  # Merge results from parallel runs
  merge_timeout 3600
end
