# frozen_string_literal: true

require "test_helper"

class UsageCredits::SubscriptionTermsTest < ActiveSupport::TestCase
  TestPlan = Struct.new(
    :name,
    :credits_per_period,
    :signup_bonus_credits,
    :trial_credits,
    :fulfillment_period_display,
    :rollover_enabled,
    :expire_credits_on_cancel,
    :credit_expiration_period,
    keyword_init: true
  )

  setup do
    UsageCredits.reset!
  end

  test "from_plan snapshots every commercial term and retains the callback plan" do
    configured_plan = build_plan

    terms = UsageCredits::SubscriptionTerms.from_plan(
      configured_plan,
      processor_plan_id: "price_pro_monthly"
    )

    assert_equal :pro, terms.name
    assert_equal "price_pro_monthly", terms.processor_plan_id
    assert_equal 100, terms.credits_per_period
    assert_equal 25, terms.signup_bonus_credits
    assert_equal 10, terms.trial_credits
    assert_equal "1 month", terms.fulfillment_period_display
    assert_equal 1.month, terms.parsed_fulfillment_period
    assert terms.rollover_enabled
    assert terms.expire_credits_on_cancel
    assert_equal 2.days.to_i, terms.credit_expiration_period_seconds
    assert_same configured_plan, terms.configured_plan
    assert_same configured_plan, terms.callback_plan
    assert terms.frozen?
  end

  test "from_plan returns nil when no configured plan exists" do
    assert_nil UsageCredits::SubscriptionTerms.from_plan(nil, processor_plan_id: "missing")
  end

  test "from_metadata accepts indifferent keys and strict serialized values" do
    terms = UsageCredits::SubscriptionTerms.from_metadata(
      {
        "plan_name" => "snapshot_pro",
        "credits_per_period" => "100",
        "signup_bonus_credits" => "25",
        "trial_credits" => "10",
        "fulfillment_period" => "2 weeks",
        "rollover_enabled" => "1",
        "expire_credits_on_cancel" => "true",
        "credit_expiration_period" => 86_400.to_s
      },
      processor_plan_id: :price_snapshot
    )

    assert_equal :snapshot_pro, terms.name
    assert_equal "price_snapshot", terms.processor_plan_id
    assert_equal 100, terms.credits_per_period
    assert_equal 25, terms.signup_bonus_credits
    assert_equal 10, terms.trial_credits
    assert_equal 2.weeks, terms.parsed_fulfillment_period
    assert terms.rollover_enabled
    assert terms.expire_credits_on_cancel
    assert_equal 1.day.to_i, terms.credit_expiration_period_seconds
    assert_same terms, terms.callback_plan
  end

  test "from_metadata requires the three canonical snapshot fields" do
    %i[credits_per_period fulfillment_period rollover_enabled].each do |key|
      assert_nil UsageCredits::SubscriptionTerms.from_metadata(
        valid_metadata.except(key),
        processor_plan_id: "price_missing_#{key}"
      )
    end
  end

  test "serialized booleans accept only explicit true and false representations" do
    UsageCredits::SubscriptionTerms::TRUE_VALUES.each do |value|
      terms = terms_from_metadata(rollover_enabled: value, expire_credits_on_cancel: value)
      assert terms.rollover_enabled, "expected #{value.inspect} to parse as true"
      assert terms.expire_credits_on_cancel, "expected #{value.inspect} to parse as true"
    end

    UsageCredits::SubscriptionTerms::FALSE_VALUES.each do |value|
      terms = terms_from_metadata(rollover_enabled: value, expire_credits_on_cancel: value)
      assert_not terms.rollover_enabled, "expected #{value.inspect} to parse as false"
      assert_not terms.expire_credits_on_cancel, "expected #{value.inspect} to parse as false"
    end
  end

  test "serialized booleans reject ambiguous values" do
    [nil, "", "TRUE", "yes", 2].each do |value|
      error = assert_raises(ArgumentError) do
        terms_from_metadata(rollover_enabled: value)
      end
      assert_includes error.message, "rollover_enabled must be true or false"
    end

    ["TRUE", "yes", 2].each do |value|
      error = assert_raises(ArgumentError) do
        terms_from_metadata(expire_credits_on_cancel: value)
      end
      assert_includes error.message, "expire_credits_on_cancel must be true or false"
    end
  end

  test "missing optional metadata falls back to the configured plan" do
    configured_plan = build_plan(name: :configured_fallback, credit_expiration_period: 3.days)
    metadata = valid_metadata.except(
      :plan_name,
      :subscription_name,
      :expire_credits_on_cancel,
      :credit_expiration_period
    )

    terms = UsageCredits::SubscriptionTerms.from_metadata(
      metadata,
      processor_plan_id: "price_fallback",
      configured_plan: configured_plan
    )

    assert_equal :configured_fallback, terms.name
    assert terms.expire_credits_on_cancel
    assert_equal 3.days.to_i, terms.credit_expiration_period_seconds
    assert_same configured_plan, terms.callback_plan
  end

  test "explicit serialized false and zero override a truthy configured fallback" do
    configured_plan = build_plan
    terms = UsageCredits::SubscriptionTerms.from_metadata(
      valid_metadata.merge(
        expire_credits_on_cancel: "0",
        credit_expiration_period: "0"
      ),
      processor_plan_id: "price_override",
      configured_plan: configured_plan
    )

    assert_not terms.expire_credits_on_cancel
    assert_equal 0, terms.credit_expiration_period_seconds
  end

  test "credits per period must be a positive whole number" do
    [nil, 0, -1, "0", "-1", 1.5, "1.5", Float::NAN, Float::INFINITY, "many"].each do |value|
      assert_raises(ArgumentError, "expected #{value.inspect} to be rejected") do
        terms_from_metadata(credits_per_period: value)
      end
    end
  end

  test "signup and trial credits must be non-negative whole numbers" do
    %i[signup_bonus_credits trial_credits].each do |field|
      [-1, "-1", 1.5, "1.5", Float::NAN, Float::INFINITY, "many"].each do |value|
        assert_raises(ArgumentError, "expected #{field}=#{value.inspect} to be rejected") do
          terms_from_metadata(field => value)
        end
      end
    end
  end

  test "credit expiration period allows blank immediate expiry and rejects invalid values" do
    [nil, "", 0, "0"].each do |value|
      assert_equal 0, terms_from_metadata(credit_expiration_period: value).credit_expiration_period_seconds
    end

    [-1, "-1", 1.5, "1.5", Float::NAN, Float::INFINITY, "later"].each do |value|
      assert_raises(ArgumentError, "expected #{value.inspect} to be rejected") do
        terms_from_metadata(credit_expiration_period: value)
      end
    end
  end

  test "persisted cadence ignores later operator minimums but never the hard one-second floor" do
    UsageCredits.configuration.min_fulfillment_period = 1.day

    terms = terms_from_metadata(fulfillment_period: "1 second")
    assert_equal 1.second, terms.parsed_fulfillment_period

    ["0 seconds", "0.second", "invalid", "1 fortnight"].each do |period|
      assert_raises(ArgumentError, "expected #{period.inspect} to be rejected") do
        terms_from_metadata(fulfillment_period: period)
      end
    end
  end

  test "snapshots are immutable after construction" do
    terms = terms_from_metadata

    assert_raises(FrozenError) do
      terms.instance_variable_set(:@credits_per_period, 1_000_000)
    end
    assert_equal 100, terms.credits_per_period
  end

  private

  def build_plan(**overrides)
    attributes = {
      name: :pro,
      credits_per_period: 100,
      signup_bonus_credits: 25,
      trial_credits: 10,
      fulfillment_period_display: "1 month",
      rollover_enabled: true,
      expire_credits_on_cancel: true,
      credit_expiration_period: 2.days
    }.merge(overrides)

    TestPlan.new(**attributes)
  end

  def valid_metadata
    {
      plan_name: "snapshot_pro",
      credits_per_period: "100",
      signup_bonus_credits: "25",
      trial_credits: "10",
      fulfillment_period: "1 month",
      rollover_enabled: "true",
      expire_credits_on_cancel: "false",
      credit_expiration_period: "0"
    }
  end

  def terms_from_metadata(overrides = {})
    UsageCredits::SubscriptionTerms.from_metadata(
      valid_metadata.merge(overrides),
      processor_plan_id: "price_snapshot"
    )
  end
end
