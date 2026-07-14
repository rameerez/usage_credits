# frozen_string_literal: true

source "https://rubygems.org"

# Runtime dependencies are specified in usage_credits.gemspec
gemspec

# Ecosystem development can test an unreleased wallets version without
# weakening the runtime gemspec constraint. CI/release builds omit this and
# resolve the published dependency normally.
if ENV["WALLETS_PATH"]
  gem "wallets", path: File.expand_path(ENV.fetch("WALLETS_PATH"), __dir__)
end

# Build & release tools
gem "rake", "~> 13.0"

group :development do
  gem "appraisal"
  gem "bundler-audit", "~> 0.9"
  gem "web-console"

  # Code quality
  gem "standard", ">= 1.35.1"
  gem "rubocop", "~> 1.0"
  gem "rubocop-minitest", "~> 0.35"
  gem "rubocop-performance", "~> 1.0"
end

group :test do
  gem "minitest", "~> 5.0"
  gem "mocha"
  gem "simplecov", require: false
  gem "vcr"
  gem "webmock"

  # Payment processors (for testing Pay integration)
  # Note: stripe version is specified in Appraisals per Pay version
  gem "braintree", ">= 2.92.0"
  gem "lemonsqueezy", "~> 1.0"
  gem "paddle", "~> 2.6"

  # Receipts
  gem "prawn"
  gem "receipts"

  # Database adapters (for multi-database testing)
  gem "sqlite3", ">= 2.9.5"
  gem "pg"
  gem "mysql2"

  # Dummy Rails app
  gem "bootsnap", require: false
  gem "puma"
  gem "importmap-rails"
  gem "sprockets-rails"
  gem "stimulus-rails"
  gem "turbo-rails"

  # Fix RDoc version conflict (Ruby 3.4+ ships with 7.0.3)
  gem "rdoc", ">= 7.0"
end
