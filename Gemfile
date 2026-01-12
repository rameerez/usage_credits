# frozen_string_literal: true

source "https://rubygems.org"

# Runtime dependencies are specified in usage_credits.gemspec
gemspec

# Build & release tools
gem "rake", "~> 13.0"

group :development do
  gem "appraisal"
  gem "web-console"

  # Code quality
  gem "standard"
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

  # Database adapters
  gem "sqlite3"
  gem "pg"

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
