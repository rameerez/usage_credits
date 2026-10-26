# frozen_string_literal: true

# The generated gemfiles intentionally retain the root Gemfile's conditional
# WALLETS_PATH hook for coordinated pre-release CI. Appraisal cannot emit that
# runtime conditional itself, so preserve the postamble when regenerating.

# Pay checks processor gem versions at boot: Pay 12.3 requires stripe ~> 20 and
# paddle ~> 3 (from the root Gemfile). Pay 11 and Pay 12.0 to 12.2 require
# stripe ~> 19 and paddle ~> 2.5. paddle 3 needs Ruby 3.3+, so Ruby 3.2 runs
# the bundles that use paddle 2.

# Test minimum supported Rails version (with latest Pay)
appraise "rails-7.2" do
  gem "rails", "~> 7.2.0"
  gem "pay", "~> 12.3"
  gem "stripe", "~> 20.0"
end

# Test latest Rails version (with latest Pay) - this is the default/main Gemfile anyway
appraise "rails-8.1" do
  gem "rails", "~> 8.1.0"
  gem "pay", "~> 12.3"
  gem "stripe", "~> 20.0"
end

# Test the Pay 12 releases that keep stripe ~> 19 and paddle ~> 2.5 (with
# latest Rails). The gemspec excludes 12.0.0 and 12.1.0 for their advisories.
appraise "pay-12-stripe-19" do
  gem "pay", ">= 12.1.1", "< 12.3"
  gem "stripe", "~> 19.0"
  gem "rails", "~> 8.1.0"

  group :test do
    gem "paddle", "~> 2.6"
  end
end

# Test the latest Pay 11 release (with latest Rails)
appraise "pay-11" do
  gem "pay", ">= 11.6.2", "< 12.0"
  gem "stripe", "~> 19.0"
  gem "rails", "~> 8.1.0"

  group :test do
    gem "paddle", "~> 2.6"
  end
end

# Test the literal minimum supported dependency set: the exact minimum secure
# Pay version with the minimum supported Rails version
appraise "pay-minimum" do
  gem "pay", "= 11.6.2"
  gem "stripe", "~> 19.0"
  gem "rails", "~> 7.2.0"

  group :test do
    gem "paddle", "~> 2.6"
  end
end
