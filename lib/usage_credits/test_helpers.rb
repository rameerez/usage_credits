# frozen_string_literal: true

module UsageCredits
  # Test helpers for UsageCredits
  module TestHelpers
    # Add credits to a user's wallet for testing
    def add_test_credits(user, amount)
      user.credit_wallet.add_credits(
        amount,
        metadata: { source: :test },
        category: :test_credits
      )
    end

    # Set up a test operation
    def define_test_operation(name = :test_operation, cost: 10)
      UsageCredits.define_operation(name) do |op|
        op.cost cost
      end
    end

    # Set up a test credit pack
    def define_test_pack(name = :test_pack, credits: 1000, price_cents: 4900)
      UsageCredits.define_pack(name) do |pack|
        pack.credits credits
        pack.price_cents price_cents
      end
    end

    # Set up a test subscription rule
    def define_test_subscription_rule(name = :test_plan, monthly_credits: 10_000)
      UsageCredits.define_subscription_rule(name) do |rule|
        rule.monthly_credits monthly_credits
      end
    end

    # Reset all test data
    def reset_usage_credits!
      UsageCredits.reset!
    end
  end
end

# RSpec configuration if RSpec is available
if defined?(RSpec)
  RSpec.configure do |config|
    config.include UsageCredits::TestHelpers
  end
end
