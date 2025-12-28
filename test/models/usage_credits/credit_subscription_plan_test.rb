# frozen_string_literal: true

require "test_helper"

# ============================================================================
# CREDIT SUBSCRIPTION PLAN TEST SUITE
# ============================================================================
#
# This test suite tests the CreditSubscriptionPlan DSL model which defines
# subscription plans that give credits to users on a recurring basis.
#
# The DSL allows developers to configure:
#   - Credit amounts per period (gives/every)
#   - Signup bonuses and trial credits
#   - Rollover behavior (expire vs. rollover unused credits)
#   - Payment processor integration (Stripe, etc.)
#   - Credit expiration rules on cancellation
#
# The actual credit fulfillment is handled by PaySubscriptionExtension,
# which monitors subscription events and adds credits accordingly.
#
# ============================================================================

class UsageCredits::CreditSubscriptionPlanTest < ActiveSupport::TestCase
  setup do
    UsageCredits.reset!
  end

  teardown do
    UsageCredits.reset!
  end

  # ========================================
  # BASIC CREATION
  # ========================================

  test "creates plan with name" do
    plan = UsageCredits::CreditSubscriptionPlan.new(:basic)
    assert_equal :basic, plan.name
  end

  test "creates plan with DSL block" do
    plan = UsageCredits::CreditSubscriptionPlan.new(:pro)
    plan.instance_eval do
      gives 1000.credits.every(:month)
      signup_bonus 100.credits
    end

    assert_equal 1000, plan.credits_per_period
    assert_equal 100, plan.signup_bonus_credits
  end

  test "default values are sensible" do
    plan = UsageCredits::CreditSubscriptionPlan.new(:test)

    assert_equal 0, plan.credits_per_period
    assert_equal 0, plan.signup_bonus_credits
    assert_equal 0, plan.trial_credits
    assert_equal false, plan.rollover_enabled
    assert_equal false, plan.expire_credits_on_cancel
    assert_nil plan.credit_expiration_period
    assert_equal({}, plan.metadata)
    assert_equal({}, plan.processor_plan_ids)
  end

  # ========================================
  # DSL - GIVES/EVERY (CREDITS PER PERIOD)
  # ========================================

  test "gives sets credits per period" do
    plan = UsageCredits::CreditSubscriptionPlan.new(:test)
    plan.gives(500).every(:month)

    assert_equal 500, plan.credits_per_period
    assert_equal 1.month, plan.fulfillment_period
  end

  test "gives with Cost::Fixed object sets credits and period" do
    plan = UsageCredits::CreditSubscriptionPlan.new(:test)
    plan.gives(1000.credits.every(:month))

    assert_equal 1000, plan.credits_per_period
    assert_equal 1.month, plan.fulfillment_period
  end

  test "gives accepts different period units" do
    plan_weekly = UsageCredits::CreditSubscriptionPlan.new(:weekly)
    plan_weekly.gives(100).every(:week)
    assert_equal 1.week, plan_weekly.fulfillment_period

    plan_yearly = UsageCredits::CreditSubscriptionPlan.new(:yearly)
    plan_yearly.gives(10000).every(:year)
    assert_equal 1.year, plan_yearly.fulfillment_period

    plan_days = UsageCredits::CreditSubscriptionPlan.new(:biweekly)
    plan_days.gives(200).every(14.days)
    assert_equal 14.days, plan_days.fulfillment_period
  end

  # ========================================
  # DSL - SIGNUP BONUS
  # ========================================

  test "signup_bonus sets one-time signup credits" do
    plan = UsageCredits::CreditSubscriptionPlan.new(:test)
    plan.signup_bonus(250)

    assert_equal 250, plan.signup_bonus_credits
  end

  test "signup_bonus accepts Cost::Fixed object" do
    plan = UsageCredits::CreditSubscriptionPlan.new(:test)
    plan.signup_bonus(500.credits)

    assert_equal 500, plan.signup_bonus_credits
  end

  # ========================================
  # DSL - TRIAL CREDITS
  # ========================================

  test "trial_includes sets trial period credits" do
    plan = UsageCredits::CreditSubscriptionPlan.new(:test)
    plan.trial_includes(100)

    assert_equal 100, plan.trial_credits
  end

  test "trial_includes accepts Cost::Fixed object" do
    plan = UsageCredits::CreditSubscriptionPlan.new(:test)
    plan.trial_includes(200.credits)

    assert_equal 200, plan.trial_credits
  end

  # ========================================
  # DSL - ROLLOVER BEHAVIOR
  # ========================================

  test "unused_credits :rollover enables rollover" do
    plan = UsageCredits::CreditSubscriptionPlan.new(:test)
    plan.unused_credits(:rollover)

    assert_equal true, plan.rollover_enabled
  end

  test "unused_credits :expire disables rollover" do
    plan = UsageCredits::CreditSubscriptionPlan.new(:test)
    plan.unused_credits(:expire)

    assert_equal false, plan.rollover_enabled
  end

  # ========================================
  # DSL - CREDIT EXPIRATION ON CANCEL
  # ========================================

  test "expire_after enables credit expiration with grace period" do
    plan = UsageCredits::CreditSubscriptionPlan.new(:test)
    plan.expire_after(30.days)

    assert_equal true, plan.expire_credits_on_cancel
    assert_equal 30.days, plan.credit_expiration_period
  end

  test "expire_after with nil enables immediate expiration" do
    plan = UsageCredits::CreditSubscriptionPlan.new(:test)
    plan.expire_after(nil)

    assert_equal true, plan.expire_credits_on_cancel
    assert_nil plan.credit_expiration_period
  end

  test "expire_after with zero enables immediate expiration" do
    plan = UsageCredits::CreditSubscriptionPlan.new(:test)
    plan.expire_after(0)

    assert_equal true, plan.expire_credits_on_cancel
    assert_equal 0, plan.credit_expiration_period
  end

  # ========================================
  # DSL - METADATA
  # ========================================

  test "meta sets custom metadata" do
    plan = UsageCredits::CreditSubscriptionPlan.new(:test)
    plan.meta(tier: "premium", features: ["feature1", "feature2"])

    assert_equal "premium", plan.metadata[:tier]
    assert_equal ["feature1", "feature2"], plan.metadata[:features]
  end

  test "meta merges with existing metadata" do
    plan = UsageCredits::CreditSubscriptionPlan.new(:test)
    plan.meta(key1: "value1")
    plan.meta(key2: "value2")

    assert_equal "value1", plan.metadata[:key1]
    assert_equal "value2", plan.metadata[:key2]
  end

  # ========================================
  # PAYMENT PROCESSOR INTEGRATION
  # ========================================

  test "processor_plan sets processor-specific plan ID" do
    plan = UsageCredits::CreditSubscriptionPlan.new(:test)
    plan.processor_plan(:stripe, "price_123456789")

    assert_equal "price_123456789", plan.processor_plan_ids[:stripe]
  end

  test "plan_id_for retrieves processor plan ID" do
    plan = UsageCredits::CreditSubscriptionPlan.new(:test)
    plan.processor_plan(:stripe, "price_stripe")
    plan.processor_plan(:paddle, "price_paddle")

    assert_equal "price_stripe", plan.plan_id_for(:stripe)
    assert_equal "price_paddle", plan.plan_id_for(:paddle)
  end

  test "stripe_price setter and getter" do
    plan = UsageCredits::CreditSubscriptionPlan.new(:test)
    plan.stripe_price("price_abc123")

    assert_equal "price_abc123", plan.stripe_price
    assert_equal "price_abc123", plan.plan_id_for(:stripe)
  end

  test "stripe_price returns nil when not set" do
    plan = UsageCredits::CreditSubscriptionPlan.new(:test)
    assert_nil plan.stripe_price
  end

  # ========================================
  # VALIDATION
  # ========================================

  test "validate! passes for valid plan" do
    plan = UsageCredits::CreditSubscriptionPlan.new(:basic)
    plan.gives(500).every(:month)

    assert plan.validate!
  end

  test "validate! raises for blank name" do
    plan = UsageCredits::CreditSubscriptionPlan.new("")

    error = assert_raises(ArgumentError) do
      plan.validate!
    end

    assert_includes error.message, "Name can't be blank"
  end

  test "validate! raises for zero credits per period" do
    plan = UsageCredits::CreditSubscriptionPlan.new(:test)
    plan.gives(0).every(:month)

    error = assert_raises(ArgumentError) do
      plan.validate!
    end

    assert_includes error.message, "Credits per period must be greater than 0"
  end

  test "validate! raises when fulfillment period not set" do
    plan = UsageCredits::CreditSubscriptionPlan.new(:test)
    plan.instance_variable_set(:@credits_per_period, 500)  # Set credits but not period

    error = assert_raises(ArgumentError) do
      plan.validate!
    end

    assert_includes error.message, "Fulfillment period must be set"
  end

  test "validate! raises for negative signup bonus" do
    plan = UsageCredits::CreditSubscriptionPlan.new(:test)
    plan.gives(500).every(:month)
    plan.instance_variable_set(:@signup_bonus_credits, -100)

    error = assert_raises(ArgumentError) do
      plan.validate!
    end

    assert_includes error.message, "Signup bonus credits must be greater than or equal to 0"
  end

  test "validate! raises for negative trial credits" do
    plan = UsageCredits::CreditSubscriptionPlan.new(:test)
    plan.gives(500).every(:month)
    plan.instance_variable_set(:@trial_credits, -50)

    error = assert_raises(ArgumentError) do
      plan.validate!
    end

    assert_includes error.message, "Trial credits must be greater than or equal to 0"
  end

  # ========================================
  # HELPER METHODS
  # ========================================

  test "fulfillment_period_display shows period as string" do
    plan = UsageCredits::CreditSubscriptionPlan.new(:test)
    plan.gives(500).every(:month)

    display = plan.fulfillment_period_display
    assert_includes display, "month"
  end

  test "parsed_fulfillment_period returns ActiveSupport::Duration" do
    plan = UsageCredits::CreditSubscriptionPlan.new(:test)
    plan.gives(500).every(:month)

    parsed = plan.parsed_fulfillment_period
    assert_kind_of ActiveSupport::Duration, parsed
    assert_equal 1.month.to_i, parsed.to_i
  end

  test "base_metadata includes all essential plan info" do
    plan = UsageCredits::CreditSubscriptionPlan.new(:premium)
    plan.gives(1000).every(:month)
    plan.signup_bonus(200)
    plan.trial_includes(50)
    plan.unused_credits(:rollover)
    plan.expire_after(30.days)
    plan.meta(tier: "premium")

    metadata = plan.base_metadata

    assert_equal "credit_subscription", metadata[:purchase_type]
    assert_equal :premium, metadata[:subscription_name]
    assert_includes metadata[:fulfillment_period], "month"
    assert_equal 1000, metadata[:credits_per_period]
    assert_equal 200, metadata[:signup_bonus_credits]
    assert_equal 50, metadata[:trial_credits]
    assert_equal true, metadata[:rollover_enabled]
    assert_equal true, metadata[:expire_credits_on_cancel]
    assert_equal 30.days.to_i, metadata[:credit_expiration_period]
    assert_equal({ tier: "premium" }, metadata[:metadata])
  end

  # ========================================
  # INTEGRATION WITH CONFIGURATION
  # ========================================

  test "plan registered via configuration DSL" do
    UsageCredits.configure do |config|
      config.subscription_plan :test_basic do
        gives 500.credits.every(:month)
        signup_bonus 100.credits
      end
    end

    plan = UsageCredits.find_subscription_plan(:test_basic)

    assert_not_nil plan
    assert_equal :test_basic, plan.name
    assert_equal 500, plan.credits_per_period
    assert_equal 100, plan.signup_bonus_credits
  end

  test "subscription_plans returns all registered plans" do
    UsageCredits.configure do |config|
      config.subscription_plan :basic do
        gives 100.credits.every(:month)
      end

      config.subscription_plan :pro do
        gives 1000.credits.every(:month)
      end
    end

    plans = UsageCredits.subscription_plans.values

    assert_equal 2, plans.size
    assert plans.any? { |p| p.name == :basic }
    assert plans.any? { |p| p.name == :pro }
  end

  test "find_subscription_plan_by_processor_id finds plan by processor ID" do
    UsageCredits.configure do |config|
      config.subscription_plan :stripe_plan do
        gives 500.credits.every(:month)
        stripe_price "price_stripe123"
      end
    end

    plan = UsageCredits.find_subscription_plan_by_processor_id("price_stripe123")

    assert_not_nil plan
    assert_equal :stripe_plan, plan.name
  end

  test "find_subscription_plan_by_processor_id returns nil for unknown ID" do
    plan = UsageCredits.find_subscription_plan_by_processor_id("nonexistent_price")
    assert_nil plan
  end

  # ========================================
  # EDGE CASES
  # ========================================

  test "handles very large credit amounts" do
    plan = UsageCredits::CreditSubscriptionPlan.new(:enterprise)
    plan.gives(100_000_000).every(:year)

    assert_equal 100_000_000, plan.credits_per_period
    assert plan.validate!
  end

  test "handles complex period like 14 days" do
    plan = UsageCredits::CreditSubscriptionPlan.new(:biweekly)
    plan.gives(200).every(14.days)

    assert_equal 14.days, plan.fulfillment_period
    assert_equal 14.days.to_i, plan.parsed_fulfillment_period.to_i
  end

  test "zero signup bonus and trial credits is valid" do
    plan = UsageCredits::CreditSubscriptionPlan.new(:basic)
    plan.gives(500).every(:month)
    plan.signup_bonus(0)
    plan.trial_includes(0)

    assert plan.validate!
    assert_equal 0, plan.signup_bonus_credits
    assert_equal 0, plan.trial_credits
  end

  test "plan without expire_after keeps credits forever on cancel" do
    plan = UsageCredits::CreditSubscriptionPlan.new(:test)
    plan.gives(500).every(:month)

    assert_equal false, plan.expire_credits_on_cancel
    assert_nil plan.credit_expiration_period
  end

  test "multiple processor plans can be set" do
    plan = UsageCredits::CreditSubscriptionPlan.new(:multi)
    plan.gives(500).every(:month)
    plan.processor_plan(:stripe, "price_stripe")
    plan.processor_plan(:paddle, "price_paddle")
    plan.processor_plan(:paypal, "price_paypal")

    assert_equal 3, plan.processor_plan_ids.size
    assert_equal "price_stripe", plan.plan_id_for(:stripe)
    assert_equal "price_paddle", plan.plan_id_for(:paddle)
    assert_equal "price_paypal", plan.plan_id_for(:paypal)
  end

  test "plan name can be symbol or string" do
    plan_symbol = UsageCredits::CreditSubscriptionPlan.new(:basic)
    plan_string = UsageCredits::CreditSubscriptionPlan.new("premium")

    assert_equal :basic, plan_symbol.name
    assert_equal "premium", plan_string.name
  end

  test "plan_id_for returns nil for unknown processor" do
    plan = UsageCredits::CreditSubscriptionPlan.new(:test)
    plan.processor_plan(:stripe, "price_123")

    assert_nil plan.plan_id_for(:unknown_processor)
  end

  test "create_checkout_session raises when user doesn't respond to payment_processor" do
    plan = UsageCredits::CreditSubscriptionPlan.new(:test)
    plan.gives(500).every(:month)
    plan.stripe_price("price_123")

    user_without_payment = Object.new

    error = assert_raises(ArgumentError) do
      plan.create_checkout_session(user_without_payment, success_url: "/success", cancel_url: "/cancel")
    end

    assert_includes error.message, "must respond to payment_processor"
  end

  test "create_checkout_session raises when no plan id for processor" do
    plan = UsageCredits::CreditSubscriptionPlan.new(:test)
    plan.gives(500).every(:month)
    # No stripe_price set

    user = users(:rich_user)

    error = assert_raises(ArgumentError) do
      plan.create_checkout_session(user, success_url: "/success", cancel_url: "/cancel", processor: :stripe)
    end

    assert_includes error.message, "No Stripe plan ID configured"
  end

  test "create_checkout_session raises when fulfillment_period not set" do
    plan = UsageCredits::CreditSubscriptionPlan.new(:test)
    plan.instance_variable_set(:@credits_per_period, 500)  # Set credits but not period
    plan.stripe_price("price_123")

    user = users(:rich_user)

    error = assert_raises(ArgumentError) do
      plan.create_checkout_session(user, success_url: "/success", cancel_url: "/cancel")
    end

    assert_includes error.message, "No fulfillment period configured"
  end

  test "CreditGiver chain works correctly" do
    plan = UsageCredits::CreditSubscriptionPlan.new(:test)

    # This returns a CreditGiver, then .every returns the plan
    result = plan.gives(1000).every(:week)

    assert_equal plan, result
    assert_equal 1000, plan.credits_per_period
    assert_equal 1.week, plan.fulfillment_period
  end

  test "parsed_fulfillment_period handles string periods" do
    plan = UsageCredits::CreditSubscriptionPlan.new(:test)
    plan.gives(500).every(:month)

    # Manually set a string period to test parsing
    plan.instance_variable_set(:@fulfillment_period, "1.month")

    parsed = plan.parsed_fulfillment_period

    assert_kind_of ActiveSupport::Duration, parsed
  end

  # ========================================
  # STRIPE CHECKOUT SESSION CREATION
  # ========================================

  test "create_stripe_checkout_session passes subscription_data metadata" do
    plan = UsageCredits::CreditSubscriptionPlan.new(:premium)
    plan.gives(1000).every(:month)
    plan.signup_bonus(200)
    plan.trial_includes(50)
    plan.stripe_price("price_123")

    user = users(:rich_user)

    # Mock the payment processor to verify the arguments passed
    mock_payment_processor = Minitest::Mock.new
    mock_checkout_session = OpenStruct.new(url: "https://checkout.stripe.com/test")

    # Expect checkout to be called with subscription_data but NOT payment_intent_data
    mock_payment_processor.expect(:checkout, mock_checkout_session) do |args|
      assert_equal "subscription", args[:mode]
      assert_equal "price_123", args[:line_items].first[:price]
      assert_equal 1, args[:line_items].first[:quantity]
      assert args[:subscription_data].present?, "subscription_data should be present"
      assert args[:subscription_data][:metadata].present?, "subscription_data metadata should be present"

      # Verify metadata contains all required fields
      metadata = args[:subscription_data][:metadata]
      assert_equal "credit_subscription", metadata[:purchase_type]
      assert_equal :premium, metadata[:subscription_name]
      assert_equal 1000, metadata[:credits_per_period]
      assert_equal 200, metadata[:signup_bonus_credits]
      assert_equal 50, metadata[:trial_credits]

      true
    end

    user.stub(:payment_processor, mock_payment_processor) do
      plan.create_stripe_checkout_session(user, "price_123", "/success", "/cancel")
    end

    mock_payment_processor.verify
  end

  test "create_stripe_checkout_session does not pass payment_intent_data for subscription mode" do
    plan = UsageCredits::CreditSubscriptionPlan.new(:basic)
    plan.gives(500).every(:month)
    plan.stripe_price("price_456")

    user = users(:rich_user)

    # Mock the payment processor to verify payment_intent_data is NOT passed
    mock_payment_processor = Minitest::Mock.new
    mock_checkout_session = OpenStruct.new(url: "https://checkout.stripe.com/test")

    # Verify that payment_intent_data is NOT in the arguments
    mock_payment_processor.expect(:checkout, mock_checkout_session) do |args|
      # According to Stripe API, payment_intent_data is only allowed for mode: "payment"
      # For mode: "subscription", it should not be present
      refute args.key?(:payment_intent_data), "payment_intent_data should not be present for subscription mode checkout sessions"

      # But subscription_data should be present
      assert args.key?(:subscription_data), "subscription_data should be present for subscription mode"

      true
    end

    user.stub(:payment_processor, mock_payment_processor) do
      plan.create_stripe_checkout_session(user, "price_456", "/success", "/cancel")
    end

    mock_payment_processor.verify
  end

  test "create_checkout_session delegates to create_stripe_checkout_session for stripe processor" do
    plan = UsageCredits::CreditSubscriptionPlan.new(:test)
    plan.gives(500).every(:month)
    plan.stripe_price("price_789")

    user = users(:rich_user)

    mock_payment_processor = Minitest::Mock.new
    mock_checkout_session = OpenStruct.new(url: "https://checkout.stripe.com/test")

    mock_payment_processor.expect(:checkout, mock_checkout_session) do |_args|
      true
    end

    user.stub(:payment_processor, mock_payment_processor) do
      result = plan.create_checkout_session(
        user,
        success_url: "/success",
        cancel_url: "/cancel",
        processor: :stripe
      )

      assert_equal "https://checkout.stripe.com/test", result.url
    end

    mock_payment_processor.verify
  end

  test "create_checkout_session includes all plan configuration in metadata" do
    plan = UsageCredits::CreditSubscriptionPlan.new(:enterprise)
    plan.gives(10_000).every(:month)
    plan.signup_bonus(1_000)
    plan.trial_includes(500)
    plan.unused_credits(:rollover)
    plan.expire_after(30.days)
    plan.meta(tier: "enterprise", max_users: 100)
    plan.stripe_price("price_enterprise")

    user = users(:rich_user)

    mock_payment_processor = Minitest::Mock.new
    mock_checkout_session = OpenStruct.new(url: "https://checkout.stripe.com/test")

    mock_payment_processor.expect(:checkout, mock_checkout_session) do |args|
      metadata = args[:subscription_data][:metadata]

      # Verify all configuration is included
      assert_equal "credit_subscription", metadata[:purchase_type]
      assert_equal :enterprise, metadata[:subscription_name]
      assert_equal 10_000, metadata[:credits_per_period]
      assert_equal 1_000, metadata[:signup_bonus_credits]
      assert_equal 500, metadata[:trial_credits]
      assert_equal true, metadata[:rollover_enabled]
      assert_equal true, metadata[:expire_credits_on_cancel]
      assert_equal 30.days.to_i, metadata[:credit_expiration_period]
      assert_equal({ tier: "enterprise", max_users: 100 }, metadata[:metadata])

      true
    end

    user.stub(:payment_processor, mock_payment_processor) do
      plan.create_checkout_session(
        user,
        success_url: "/success",
        cancel_url: "/cancel"
      )
    end

    mock_payment_processor.verify
  end
end
