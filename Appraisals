# frozen_string_literal: true

# Test minimum supported Rails version (with latest Pay)
appraise "rails-7.2" do
  gem "rails", "~> 7.2.0"
  gem "pay", ">= 11.6.2", "< 12.0"
  gem "stripe", "~> 19.0"
end

# Test latest Rails version (with latest Pay) - this is the default/main Gemfile anyway
appraise "rails-8.1" do
  gem "rails", "~> 8.1.0"
  gem "pay", ">= 11.6.2", "< 12.0"
  gem "stripe", "~> 19.0"
end

# Test the exact minimum secure supported Pay version (with latest Rails)
appraise "pay-minimum" do
  gem "pay", "= 11.6.2"
  gem "stripe", "~> 19.0"
  gem "rails", "~> 8.1.0"
end
