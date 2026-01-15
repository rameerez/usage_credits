# test/test_helper.rb

# SimpleCov must be loaded before any application code
require 'simplecov'

# Configure Rails Environment
ENV["RAILS_ENV"] = "test"

require File.expand_path("dummy/config/environment.rb", __dir__)
ActiveRecord::Migrator.migrations_paths = [File.expand_path("dummy/db/migrate", __dir__), File.expand_path("../db/migrate", __dir__)]
require "rails/test_help"
require "minitest/mock"
require "mocha/minitest"

# Filter out Minitest backtrace while allowing backtrace from other libraries
# to be shown.
Minitest.backtrace_filter = Minitest::BacktraceFilter.new

# Load fixtures from the engine
if ActiveSupport::TestCase.respond_to?(:fixture_paths=)
  ActiveSupport::TestCase.fixture_paths << File.expand_path("../fixtures", __FILE__)
  ActionDispatch::IntegrationTest.fixture_paths << File.expand_path("../fixtures", __FILE__)
elsif ActiveSupport::TestCase.respond_to?(:fixture_path=)
  ActiveSupport::TestCase.fixture_path = File.expand_path("../fixtures", __FILE__)
  ActionDispatch::IntegrationTest.fixture_path = ActiveSupport::TestCase.fixture_path
end
ActiveSupport::TestCase.file_fixture_path = File.expand_path("../fixtures/files", __FILE__)
ActiveSupport::TestCase.fixtures :all

# Ensure Pay extensions are loaded in test environment
Pay::Subscription.include UsageCredits::PaySubscriptionExtension unless Pay::Subscription.include?(UsageCredits::PaySubscriptionExtension)
Pay::Charge.include UsageCredits::PayChargeExtension unless Pay::Charge.include?(UsageCredits::PayChargeExtension)

class ActiveSupport::TestCase
  include ActionMailer::TestHelper
  include ActiveJob::TestHelper

  # Reset UsageCredits configuration between tests to prevent callback pollution
  teardown do
    UsageCredits.reset!
  end

  def json_fixture(name)
    JSON.parse File.read(file_fixture(name + ".json"))
  end

  # Add a helper to quickly give credits to a user
  def give_credits(user, amount, reason: "test")
    user.credit_wallet.give_credits(amount, reason: reason)
  end

  # Helper to create a customer for testing
  def create_customer
    Pay::Customer.create!(
      owner: @user,
      processor: :stripe,
      processor_id: "cus_#{SecureRandom.hex(12)}"
    )
  end
end
