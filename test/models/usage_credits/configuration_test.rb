# frozen_string_literal: true

require "test_helper"

# ============================================================================
# CONFIGURATION TEST SUITE
# ============================================================================
#
# This test suite tests the Configuration class which is the single source
# of truth for all gem settings.
#
# Tests cover:
#   - Configuration initialization and defaults
#   - Setting and validation of configuration options
#   - DSL methods for defining operations, packs, and plans
#   - Configuration validation
#   - Minimum fulfillment period configuration (for dev/test fast iteration)
#
# ============================================================================

class UsageCredits::ConfigurationTest < ActiveSupport::TestCase
  setup do
    UsageCredits.reset!
    @config = UsageCredits.configuration
  end

  teardown do
    UsageCredits.reset!
  end

  # ========================================
  # INITIALIZATION & DEFAULTS
  # ========================================

  test "initializes with sensible defaults" do
    assert_equal :usd, @config.default_currency
    assert_equal :ceil, @config.rounding_strategy
    assert_equal 5.minutes, @config.fulfillment_grace_period
    assert_equal 1.day, @config.min_fulfillment_period
    assert_equal false, @config.allow_negative_balance
    assert_nil @config.low_balance_threshold
    assert_nil @config.low_balance_callback
  end

  test "initializes empty data stores" do
    assert_equal({}, @config.operations)
    assert_equal({}, @config.credit_packs)
    assert_equal({}, @config.credit_subscription_plans)
  end

  test "credit_formatter default formats credits correctly" do
    assert_equal "100 credits", @config.credit_formatter.call(100)
    assert_equal "1 credits", @config.credit_formatter.call(1)
  end

  # ========================================
  # MIN_FULFILLMENT_PERIOD CONFIGURATION
  # ========================================

  test "default min_fulfillment_period is 1.day" do
    assert_equal 1.day, @config.min_fulfillment_period
  end

  test "can set min_fulfillment_period to shorter duration" do
    @config.min_fulfillment_period = 2.seconds

    assert_equal 2.seconds, @config.min_fulfillment_period
  end

  test "can set min_fulfillment_period to 1.second" do
    @config.min_fulfillment_period = 1.second

    assert_equal 1.second, @config.min_fulfillment_period
  end

  test "can set min_fulfillment_period to longer duration" do
    @config.min_fulfillment_period = 1.week

    assert_equal 1.week, @config.min_fulfillment_period
  end

  test "min_fulfillment_period setter validates ActiveSupport::Duration type" do
    error = assert_raises(ArgumentError) do
      @config.min_fulfillment_period = "1.day"
    end

    assert_includes error.message, "must be an ActiveSupport::Duration"
  end

  test "min_fulfillment_period setter validates minimum 1 second" do
    error = assert_raises(ArgumentError) do
      @config.min_fulfillment_period = 0.5.seconds
    end

    assert_includes error.message, "must be at least 1 second"
  end

  test "min_fulfillment_period setter rejects zero" do
    error = assert_raises(ArgumentError) do
      @config.min_fulfillment_period = 0.seconds
    end

    assert_includes error.message, "must be at least 1 second"
  end

  test "min_fulfillment_period can be set via configure block" do
    UsageCredits.configure do |config|
      config.min_fulfillment_period = 5.seconds
    end

    assert_equal 5.seconds, UsageCredits.configuration.min_fulfillment_period
  end

  test "min_fulfillment_period affects period validation in plans" do
    UsageCredits.configuration.min_fulfillment_period = 1.hour

    # Should reject periods shorter than 1.hour
    error = assert_raises(ArgumentError) do
      UsageCredits.configure do |config|
        config.subscription_plan :test_plan do
          gives 100.credits.every(30.minutes)
        end
      end
    end

    assert_includes error.message, "Period must be at least"
  end

  test "min_fulfillment_period allows periods meeting minimum in plans" do
    UsageCredits.configuration.min_fulfillment_period = 2.seconds

    # Should accept 2.seconds
    UsageCredits.configure do |config|
      config.subscription_plan :fast_plan do
        gives 100.credits.every(2.seconds)
      end
    end

    plan = UsageCredits.find_subscription_plan(:fast_plan)
    assert_equal 2.seconds, plan.fulfillment_period
  end

  # ========================================
  # DEVELOPMENT MODE CONFIGURATION
  # ========================================

  test "supports development mode fast iteration pattern" do
    # Simulate what a developer would do in their initializer
    UsageCredits.configure do |config|
      # In development mode, allow very short periods for testing
      config.min_fulfillment_period = 2.seconds if Rails.env.test?
    end

    # Should now accept 2.second periods
    UsageCredits.configure do |config|
      config.subscription_plan :dev_plan do
        gives 10.credits.every(2.seconds)
      end
    end

    plan = UsageCredits.find_subscription_plan(:dev_plan)
    assert_equal 2.seconds, plan.fulfillment_period
    assert_equal 10, plan.credits_per_period
  end

  # ========================================
  # FULFILLMENT_GRACE_PERIOD CONFIGURATION
  # ========================================

  test "default fulfillment_grace_period is 5.minutes" do
    assert_equal 5.minutes, @config.fulfillment_grace_period
  end

  test "can set fulfillment_grace_period" do
    @config.fulfillment_grace_period = 10.minutes

    assert_equal 10.minutes, @config.fulfillment_grace_period
  end

  test "fulfillment_grace_period setter validates ActiveSupport::Duration type" do
    error = assert_raises(ArgumentError) do
      @config.fulfillment_grace_period = "5 minutes"
    end

    assert_includes error.message, "must be an ActiveSupport::Duration"
  end

  test "fulfillment_grace_period setter converts nil to 1.second" do
    @config.fulfillment_grace_period = nil

    assert_equal 1.second, @config.fulfillment_grace_period
  end

  test "fulfillment_grace_period setter converts 0 to 1.second" do
    @config.fulfillment_grace_period = 0

    assert_equal 1.second, @config.fulfillment_grace_period
  end

  # ========================================
  # CURRENCY CONFIGURATION
  # ========================================

  test "can set valid currency" do
    @config.default_currency = :eur
    assert_equal :eur, @config.default_currency
  end

  test "currency setter accepts string and converts to symbol" do
    @config.default_currency = "gbp"
    assert_equal :gbp, @config.default_currency
  end

  test "currency setter is case-insensitive" do
    @config.default_currency = "USD"
    assert_equal :usd, @config.default_currency
  end

  test "currency setter raises for invalid currency" do
    error = assert_raises(ArgumentError) do
      @config.default_currency = :jpy
    end

    assert_includes error.message, "Invalid currency"
  end

  # ========================================
  # ROUNDING STRATEGY CONFIGURATION
  # ========================================

  test "can set valid rounding strategy" do
    @config.rounding_strategy = :floor
    assert_equal :floor, @config.rounding_strategy

    @config.rounding_strategy = :round
    assert_equal :round, @config.rounding_strategy
  end

  test "rounding strategy setter accepts string" do
    @config.rounding_strategy = "floor"
    assert_equal :floor, @config.rounding_strategy
  end

  test "rounding strategy setter defaults to :ceil for invalid value" do
    @config.rounding_strategy = :invalid
    assert_equal :ceil, @config.rounding_strategy
  end

  # ========================================
  # LOW BALANCE CONFIGURATION
  # ========================================

  test "can set low_balance_threshold" do
    @config.low_balance_threshold = 100
    assert_equal 100, @config.low_balance_threshold
  end

  test "low_balance_threshold setter converts to integer" do
    @config.low_balance_threshold = "50"
    assert_equal 50, @config.low_balance_threshold
  end

  test "low_balance_threshold setter raises for negative value" do
    error = assert_raises(ArgumentError) do
      @config.low_balance_threshold = -10
    end

    assert_includes error.message, "must be greater than or equal to zero"
  end

  test "low_balance_threshold can be set to nil" do
    @config.low_balance_threshold = 100
    @config.low_balance_threshold = nil

    assert_nil @config.low_balance_threshold
  end

  test "on_low_balance sets callback" do
    callback_called = false
    @config.on_low_balance { |user| callback_called = true }

    assert_not_nil @config.low_balance_callback
    @config.low_balance_callback.call(nil)
    assert callback_called
  end

  test "on_low_balance requires block" do
    error = assert_raises(ArgumentError) do
      @config.on_low_balance
    end

    assert_includes error.message, "Block is required"
  end

  # ========================================
  # CREDIT FORMATTER CONFIGURATION
  # ========================================

  test "format_credits sets custom formatter" do
    @config.format_credits { |amount| "#{amount} pts" }

    assert_equal "100 pts", @config.credit_formatter.call(100)
  end

  # ========================================
  # VALIDATION
  # ========================================

  test "validate! passes for valid configuration" do
    assert @config.validate!
  end

  test "validate! raises for invalid currency" do
    @config.instance_variable_set(:@default_currency, :invalid)

    error = assert_raises(ArgumentError) do
      @config.validate!
    end

    assert_includes error.message, "Invalid currency"
  end

  test "validate! raises for negative threshold" do
    @config.instance_variable_set(:@low_balance_threshold, -100)

    error = assert_raises(ArgumentError) do
      @config.validate!
    end

    assert_includes error.message, "must be greater than or equal to zero"
  end

  test "validate! raises for invalid rounding strategy" do
    @config.instance_variable_set(:@rounding_strategy, :invalid)

    error = assert_raises(ArgumentError) do
      @config.validate!
    end

    assert_includes error.message, "Invalid rounding strategy"
  end

  # ========================================
  # DSL METHODS
  # ========================================

  test "operation method creates and stores operation" do
    op = @config.operation(:test_op) do
      costs 10.credits
    end

    assert_equal :test_op, op.name
    assert_equal op, @config.operations[:test_op]
  end

  test "operation method requires block" do
    error = assert_raises(ArgumentError) do
      @config.operation(:test_op)
    end

    assert_includes error.message, "Block is required"
  end

  test "credit_pack method creates and stores pack" do
    pack = @config.credit_pack(:starter) do
      gives 100.credits
      costs 10.dollars
    end

    assert_equal :starter, pack.name
    assert_equal pack, @config.credit_packs[:starter]
  end

  test "credit_pack method requires block" do
    error = assert_raises(ArgumentError) do
      @config.credit_pack(:starter)
    end

    assert_includes error.message, "Block is required"
  end

  test "subscription_plan method creates and stores plan" do
    plan = @config.subscription_plan(:basic) do
      gives 100.credits.every(:month)
    end

    assert_equal :basic, plan.name
    assert_equal plan, @config.credit_subscription_plans[:basic]
  end

  test "subscription_plan method requires block" do
    error = assert_raises(ArgumentError) do
      @config.subscription_plan(:basic)
    end

    assert_includes error.message, "Block is required"
  end

  test "find_subscription_plan_by_processor_id finds correct plan" do
    @config.subscription_plan(:stripe_plan) do
      gives 100.credits.every(:month)
      stripe_price "price_123"
    end

    found = @config.find_subscription_plan_by_processor_id("price_123")

    assert_not_nil found
    assert_equal :stripe_plan, found.name
  end

  test "find_subscription_plan_by_processor_id returns nil for unknown ID" do
    found = @config.find_subscription_plan_by_processor_id("unknown_id")

    assert_nil found
  end
end
