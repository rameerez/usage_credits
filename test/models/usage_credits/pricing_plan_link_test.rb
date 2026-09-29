# frozen_string_literal: true

require "test_helper"

# ============================================================================
# PRICING PLAN LINK TEST SUITE
# ============================================================================
#
# `pricing_plan :key` lets a subscription plan read its Stripe price IDs from
# the pricing_plans gem, so prices are declared once. pricing_plans is a soft
# dependency and isn't in this test bundle, so these tests stand in a minimal
# registry. The whole contract usage_credits relies on is:
#
#   PricingPlans::Registry.plan(key).stripe_price
#
# where `plan` raises (or returns nil) for an unknown key, and `stripe_price`
# returns a String, a Hash of period => price ID, or nil.
#
# ============================================================================

class PricingPlanLinkTest < ActiveSupport::TestCase
  # Mirrors how pricing_plans stores prices: a String becomes { id: "..." }
  FakePricingPlan = Struct.new(:key, :stripe_price)

  setup do
    skip "the real pricing_plans gem is loaded" if defined?(::PricingPlans)
  end

  # Remove only the stand-in this test defined: a skipped test must leave the real gem alone
  teardown do
    Object.send(:remove_const, :PricingPlans) if @stand_in_defined
  end

  # Defines a minimal PricingPlans::Registry that behaves like the real one
  def configure_pricing_plans(plans)
    unless defined?(::PricingPlans)
      @stand_in_defined = true
      Object.const_set(:PricingPlans, Module.new)
      ::PricingPlans.const_set(:PlanNotFoundError, Class.new(StandardError))
      ::PricingPlans.const_set(:Registry, Class.new do
        class << self
          attr_accessor :plans

          def plan(key)
            plans.fetch(key.to_sym) { raise ::PricingPlans::PlanNotFoundError, "Plan #{key} not found" }
          end
        end
      end)
    end

    ::PricingPlans::Registry.plans = plans.to_h do |key, stripe_price|
      stripe_price = {id: stripe_price} if stripe_price.is_a?(String)
      [key, FakePricingPlan.new(key, stripe_price)]
    end
  end

  def linked_plan(name = :pro, &block)
    UsageCredits.subscription_plan(name) do
      pricing_plan
      gives 300.credits.every(:month)
      unused_credits :expire
      instance_eval(&block) if block
    end
  end

  # ========================================
  # READING PRICES
  # ========================================

  test "a single String price reads back as a single price" do
    configure_pricing_plans(pro: "price_pro")
    plan = linked_plan

    assert_equal "price_pro", plan.stripe_price
    assert_equal({default: "price_pro"}, plan.stripe_prices)
    assert plan.matches_processor_id?("price_pro")
    refute plan.matches_processor_id?("price_other")
  end

  test "a registry that returns a bare String price is also supported" do
    configure_pricing_plans({})
    ::PricingPlans::Registry.plans = {pro: FakePricingPlan.new(:pro, "price_bare")}
    plan = linked_plan

    assert_equal "price_bare", plan.stripe_price
    assert plan.matches_processor_id?("price_bare")
  end

  test "a Hash of prices reads back with every interval, including quarterly" do
    configure_pricing_plans(pro: {month: "price_m", year: "price_y", quarter: "price_q"})
    plan = linked_plan

    assert_equal({month: "price_m", year: "price_y", quarter: "price_q"}, plan.stripe_price)
    assert_equal({month: "price_m", year: "price_y", quarter: "price_q"}, plan.stripe_prices)
    assert_equal "price_q", plan.stripe_price(:quarter)
    assert_equal "price_m", plan.plan_id_for(:stripe, period: :month)
    %w[price_m price_y price_q].each { |id| assert plan.matches_processor_id?(id), id }
  end

  test "an :id price alongside intervals counts as one more price" do
    configure_pricing_plans(pro: {id: "price_default", year: "price_y"})
    plan = linked_plan

    assert_equal({id: "price_default", year: "price_y"}, plan.stripe_prices)
    assert plan.matches_processor_id?("price_default")
    assert plan.matches_processor_id?("price_y")
  end

  test "any interval key counts, and String keys are normalized to symbols" do
    configure_pricing_plans(pro: {"week" => "price_w", "semester" => "price_s"})
    plan = linked_plan

    assert_equal({week: "price_w", semester: "price_s"}, plan.stripe_prices)
    assert plan.matches_processor_id?("price_s")
  end

  test "blank and non-String price values are skipped" do
    configure_pricing_plans(pro: {month: "price_m", year: nil, quarter: "", legacy: 123, nested: {id: "price_n"}})
    plan = linked_plan

    assert_equal({month: "price_m"}, plan.stripe_prices)
    refute plan.matches_processor_id?(nil)
    refute plan.matches_processor_id?("")
    refute plan.matches_processor_id?("price_n")
  end

  test "a pricing plan with no Stripe price matches nothing" do
    configure_pricing_plans(pro: nil)
    plan = linked_plan

    assert_nil plan.stripe_price
    assert_equal({}, plan.stripe_prices)
    assert_equal({}, plan.processor_plan_ids)
    refute plan.matches_processor_id?("price_anything")
  end

  test "a pricing plan whose every price is blank matches nothing" do
    configure_pricing_plans(pro: {month: nil, year: ""})
    plan = linked_plan

    assert_nil plan.stripe_price
    assert_equal({}, plan.stripe_prices)
  end

  # ========================================
  # CHOOSING THE PRICING PLAN
  # ========================================

  test "pricing_plan with no argument links the pricing plan of the same name" do
    configure_pricing_plans(pro: "price_pro", team: "price_team")

    assert_equal :pro, linked_plan(:pro).pricing_plan_key
    assert_equal "price_team", linked_plan(:team).stripe_price
  end

  test "pricing_plan can link a pricing plan with a different key" do
    configure_pricing_plans(pro_2026: "price_2026")
    plan = UsageCredits.subscription_plan(:pro) do
      pricing_plan :pro_2026
      gives 300.credits.every(:month)
    end

    assert_equal :pro_2026, plan.pricing_plan_key
    assert_equal "price_2026", plan.stripe_price
  end

  test "pricing_plan accepts a String key" do
    configure_pricing_plans(pro: "price_pro")
    plan = UsageCredits.subscription_plan(:credits_pro) do
      pricing_plan "pro"
      gives 300.credits.every(:month)
    end

    assert_equal :pro, plan.pricing_plan_key
    assert_equal "price_pro", plan.stripe_price
  end

  test "pricing_plan rejects a blank key" do
    plan = UsageCredits::CreditSubscriptionPlan.new(:pro)

    assert_raises(ArgumentError) { plan.pricing_plan("") }
    assert_raises(ArgumentError) { plan.pricing_plan(nil) }
  end

  test "plans without pricing_plan are unaffected" do
    plan = UsageCredits.subscription_plan(:basic) do
      stripe_price month: "price_basic_m"
      gives 100.credits.every(:month)
    end

    assert_nil plan.pricing_plan_key
    assert_equal({stripe: {month: "price_basic_m"}}, plan.processor_plan_ids)
    assert plan.matches_processor_id?("price_basic_m")
  end

  # ========================================
  # LAZY RESOLUTION (initializer order doesn't matter)
  # ========================================

  test "usage_credits can be configured before pricing_plans is even loaded" do
    refute defined?(::PricingPlans)
    plan = linked_plan # usage_credits.rb loads first...

    configure_pricing_plans(pro: {month: "price_m", quarter: "price_q"}) # ...then pricing_plans.rb

    assert plan.matches_processor_id?("price_q")
    assert_equal plan, UsageCredits.find_subscription_plan_by_processor_id("price_q")
  end

  test "usage_credits can be configured before the pricing plan is defined" do
    configure_pricing_plans({})
    plan = linked_plan

    configure_pricing_plans(pro: "price_pro")

    assert plan.matches_processor_id?("price_pro")
  end

  test "prices are read fresh on every lookup, never cached" do
    configure_pricing_plans(pro: {month: "price_old"})
    plan = linked_plan
    assert plan.matches_processor_id?("price_old")

    configure_pricing_plans(pro: {month: "price_new"})

    assert plan.matches_processor_id?("price_new")
    refute plan.matches_processor_id?("price_old")
  end

  # ========================================
  # FAILING LOUDLY
  # ========================================

  test "a missing pricing_plans gem raises an actionable error at first resolution" do
    plan = linked_plan # defining the plan never touches pricing_plans

    error = assert_raises(UsageCredits::ConfigurationError) { plan.matches_processor_id?("price_pro") }

    assert_includes error.message, "Subscription plan :pro"
    assert_includes error.message, "pricing_plans gem isn't loaded"
    assert_includes error.message, 'gem "pricing_plans"'
  end

  test "a missing pricing plan raises an actionable error at first resolution" do
    configure_pricing_plans(team: "price_team")
    plan = linked_plan

    error = assert_raises(UsageCredits::ConfigurationError) { plan.stripe_prices }

    assert_includes error.message, "pricing_plans has no plan :pro"
    assert_includes error.message, "config/initializers/pricing_plans.rb"
    assert_kind_of ::PricingPlans::PlanNotFoundError, error.cause
  end

  test "a registry that returns nil for an unknown plan is treated as missing" do
    configure_pricing_plans({})
    ::PricingPlans::Registry.define_singleton_method(:plan) { |_key| nil }
    plan = linked_plan

    assert_raises(UsageCredits::ConfigurationError) { plan.stripe_price }
  end

  test "a broken link fails every lookup instead of silently refilling nothing" do
    configure_pricing_plans({})
    linked_plan(:pro)
    UsageCredits.subscription_plan(:basic) do
      stripe_price "price_basic"
      gives 100.credits.every(:month)
    end

    assert_raises(UsageCredits::ConfigurationError) do
      UsageCredits.find_subscription_plan_by_processor_id("price_unknown")
    end
  end

  test "ConfigurationError is a UsageCredits::Error" do
    assert_operator UsageCredits::ConfigurationError, :<, UsageCredits::Error
  end

  # ========================================
  # ONE SOURCE OF TRUTH FOR STRIPE PRICES
  # ========================================

  test "declaring stripe_price next to pricing_plan is rejected" do
    error = assert_raises(UsageCredits::ConfigurationError) do
      linked_plan { stripe_price "price_drift" }
    end

    assert_includes error.message, "Subscription plan :pro takes its Stripe prices from pricing plan :pro"
    assert_includes error.message, "remove `stripe_price`"
  end

  test "declaring stripe_price before pricing_plan is rejected too" do
    assert_raises(UsageCredits::ConfigurationError) do
      UsageCredits.subscription_plan(:pro) do
        stripe_price month: "price_drift"
        pricing_plan
        gives 300.credits.every(:month)
      end
    end
  end

  test "processor_plan(:stripe, ...) next to pricing_plan is rejected" do
    assert_raises(UsageCredits::ConfigurationError) do
      linked_plan { processor_plan(:stripe, "price_drift") }
    end
  end

  test "processor_plan(:stripe, ...) before pricing_plan is rejected too" do
    assert_raises(UsageCredits::ConfigurationError) do
      UsageCredits.subscription_plan(:pro) do
        processor_plan :stripe, month: "price_drift"
        pricing_plan
        gives 300.credits.every(:month)
      end
    end

    assert_nil UsageCredits.find_subscription_plan(:pro)
  end

  test "a rejected plan is not registered" do
    assert_raises(UsageCredits::ConfigurationError) { linked_plan { stripe_price "price_drift" } }

    assert_nil UsageCredits.find_subscription_plan(:pro)
  end

  test "other processors' plan IDs still combine with a linked pricing plan" do
    configure_pricing_plans(pro: {month: "price_m"})
    plan = linked_plan { processor_plan(:paddle, "pri_paddle") }

    assert_equal({paddle: "pri_paddle", stripe: {month: "price_m"}}, plan.processor_plan_ids)
    assert plan.matches_processor_id?("pri_paddle")
    assert plan.matches_processor_id?("price_m")
  end

  test "processor_plan_ids never mutates the declared IDs" do
    configure_pricing_plans(pro: "price_pro")
    plan = linked_plan { processor_plan(:paddle, "pri_paddle") }

    plan.processor_plan_ids
    configure_pricing_plans(pro: nil)

    assert_equal({paddle: "pri_paddle"}, plan.processor_plan_ids)
  end

  # ========================================
  # PAY INTEGRATION
  # ========================================

  test "a subscription to a quarterly price finds its plan through the link" do
    configure_pricing_plans(pro: {month: "price_m", year: "price_y", quarter: "price_q"})
    plan = linked_plan

    assert_equal plan, UsageCredits.find_subscription_plan_by_processor_id("price_q")
    assert_nil UsageCredits.find_subscription_plan_by_processor_id("price_unknown")
  end

  test "a new Pay subscription to a linked quarterly price refills credits" do
    configure_pricing_plans(pro: {month: "price_m", quarter: "price_q"})
    linked_plan { signup_bonus 50.credits }

    user = User.create!(email: "pricing_plan_link@example.com", name: "Linked Plan User")
    wallet = user.credit_wallet
    customer = Pay::Customer.create!(owner: user, processor: :fake_processor, processor_id: "cus_pricing_plan_link")

    assert_difference -> { wallet.reload.credits }, 350 do
      Pay::Subscription.create!(
        customer: customer,
        name: "default",
        processor_id: "sub_pricing_plan_link",
        processor_plan: "price_q",
        status: "active",
        quantity: 1
      )
    end

    assert UsageCredits::Fulfillment.exists?(source: Pay::Subscription.find_by!(processor_id: "sub_pricing_plan_link"))
  end

  test "checkout uses the linked pricing plan's price for the requested period" do
    configure_pricing_plans(pro: {month: "price_m", quarter: "price_q"})
    plan = linked_plan
    user = users(:rich_user)

    plan.expects(:create_stripe_checkout_session).with(user, "price_q", "/success", "/cancel").returns(:session)

    assert_equal :session, plan.create_checkout_session(user, success_url: "/success", cancel_url: "/cancel", period: :quarter)
  end

  test "single-price checkout needs no period, whether the price comes back as a bare String or as {id:}" do
    configure_pricing_plans({})
    plan = linked_plan
    user = users(:rich_user)

    [FakePricingPlan.new(:pro, "price_pro"), FakePricingPlan.new(:pro, {id: "price_pro"})].each do |pricing_plan|
      ::PricingPlans::Registry.plans = {pro: pricing_plan}
      plan.expects(:create_stripe_checkout_session).with(user, "price_pro", "/success", "/cancel").returns(:session)

      assert_equal :session, plan.create_checkout_session(user, success_url: "/success", cancel_url: "/cancel")
    end
  end

  # ========================================
  # BOOT-TIME VALIDATION
  # ========================================

  test "boot validation passes when every link resolves" do
    configure_pricing_plans(pro: "price_pro")
    linked_plan

    assert UsageCredits.configuration.validate_pricing_plan_links!
  end

  test "boot validation ignores plans without a link" do
    UsageCredits.subscription_plan(:basic) do
      stripe_price "price_basic"
      gives 100.credits.every(:month)
    end

    assert UsageCredits.configuration.validate_pricing_plan_links!
  end

  test "boot validation raises when pricing_plans isn't loaded" do
    linked_plan

    assert_raises(UsageCredits::ConfigurationError) { UsageCredits.configuration.validate_pricing_plan_links! }
  end

  test "boot validation raises when the pricing plan doesn't exist" do
    configure_pricing_plans(team: "price_team")
    linked_plan

    assert_raises(UsageCredits::ConfigurationError) { UsageCredits.configuration.validate_pricing_plan_links! }
  end

  test "boot validation warns, without raising, when the pricing plan has no Stripe price" do
    configure_pricing_plans(pro: {month: nil})
    linked_plan
    Rails.logger.expects(:warn).with(includes("pricing plan 'pro', which has no Stripe price"))

    assert UsageCredits.configuration.validate_pricing_plan_links!
  end
end
