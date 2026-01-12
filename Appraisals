# frozen_string_literal: true

# Test minimum supported Rails version (with latest Pay)
appraise "rails-7.2" do
  gem "rails", "~> 7.2.0"
  gem "pay", "~> 11.0"
  gem "stripe", "~> 18.0"
end

# Test latest Rails version (with latest Pay) - this is the default/main Gemfile anyway
appraise "rails-8.1" do
  gem "rails", "~> 8.1.0"
  gem "pay", "~> 11.0"
  gem "stripe", "~> 18.0"
end

# Test minimum supported Pay version (with latest Rails)
appraise "pay-8.3" do
  gem "pay", "~> 8.3.0"
  gem "stripe", "~> 13.0"
  gem "rails", "~> 8.1.0"
end

# Test Pay 9.0 (popular stable version with latest Rails)
appraise "pay-9.0" do
  gem "pay", "~> 9.0.0"
  gem "stripe", "~> 13.0"
  gem "rails", "~> 8.1.0"
end

# Test Pay 10.0 (with latest Rails)
appraise "pay-10.0" do
  gem "pay", "~> 10.0.0"
  gem "stripe", "~> 15.0"
  gem "rails", "~> 8.1.0"
end

# Test latest Pay version (with latest Rails)
appraise "pay-11.0" do
  gem "pay", "~> 11.0"
  gem "stripe", "~> 18.0"
  gem "rails", "~> 8.1.0"
end
