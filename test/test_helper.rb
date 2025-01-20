# test/test_helper.rb
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

class ActiveSupport::TestCase
  include ActionMailer::TestHelper
  include ActiveJob::TestHelper

  def json_fixture(name)
    JSON.parse File.read(file_fixture(name + ".json"))
  end

  # Add a helper to quickly give credits to a user
  def give_credits(user, amount, reason: "test")
    user.credit_wallet.give_credits(amount, reason: reason)
  end
end
