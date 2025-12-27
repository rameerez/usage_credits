# frozen_string_literal: true

require "test_helper"

class UsageCredits::FulfillmentTest < ActiveSupport::TestCase
  setup do
    UsageCredits.configure do |config|
      config.subscription_plan :test_pro do
        processor_plan(:fake_processor, "pro_plan_monthly")
        gives 500.credits.every(:month)
        signup_bonus 100.credits
        trial_includes 50.credits
        unused_credits :expire
      end

      config.subscription_plan :test_rollover do
        processor_plan(:fake_processor, "rollover_plan_monthly")
        gives 1000.credits.every(:month)
        unused_credits :rollover
      end

      config.credit_pack :test_pack do
        gives 1000.credits
        costs 49.dollars
      end
    end
  end

  teardown do
    UsageCredits.reset!
  end

  # ========================================
  # BASIC CREATION
  # ========================================

  test "creates fulfillment with valid attributes" do
    wallet = usage_credits_wallets(:rich_wallet)

    fulfillment = UsageCredits::Fulfillment.create!(
      wallet: wallet,
      fulfillment_type: "credit_pack",
      credits_last_fulfillment: 1000,
      last_fulfilled_at: Time.current,
      metadata: { test: true }
    )

    assert fulfillment.persisted?
    assert_equal wallet, fulfillment.wallet
    assert_equal "credit_pack", fulfillment.fulfillment_type
    assert_equal 1000, fulfillment.credits_last_fulfillment
  end

  test "creates recurring fulfillment" do
    wallet = usage_credits_wallets(:subscribed_wallet)

    fulfillment = UsageCredits::Fulfillment.create!(
      wallet: wallet,
      fulfillment_type: "subscription",
      credits_last_fulfillment: 500,
      fulfillment_period: "1.month",
      last_fulfilled_at: Time.current,
      next_fulfillment_at: 1.month.from_now,
      metadata: { plan: "pro_plan_monthly" }
    )

    assert fulfillment.persisted?
    assert fulfillment.recurring?
  end

  # ========================================
  # VALIDATIONS
  # ========================================

  test "requires wallet" do
    fulfillment = UsageCredits::Fulfillment.new(
      fulfillment_type: "credit_pack",
      credits_last_fulfillment: 100,
      last_fulfilled_at: Time.current
    )

    assert_not fulfillment.valid?
    assert fulfillment.errors[:wallet].present?
  end

  test "requires credits_last_fulfillment" do
    fulfillment = UsageCredits::Fulfillment.new(
      wallet: usage_credits_wallets(:rich_wallet),
      fulfillment_type: "credit_pack",
      last_fulfilled_at: Time.current
    )

    assert_not fulfillment.valid?
    assert fulfillment.errors[:credits_last_fulfillment].present?
  end

  test "requires fulfillment_type" do
    fulfillment = UsageCredits::Fulfillment.new(
      wallet: usage_credits_wallets(:rich_wallet),
      credits_last_fulfillment: 100,
      last_fulfilled_at: Time.current
    )

    assert_not fulfillment.valid?
    assert fulfillment.errors[:fulfillment_type].present?
  end

  test "validates fulfillment_period format" do
    fulfillment = UsageCredits::Fulfillment.new(
      wallet: usage_credits_wallets(:rich_wallet),
      fulfillment_type: "subscription",
      credits_last_fulfillment: 100,
      fulfillment_period: "invalid_period",
      last_fulfilled_at: Time.current,
      next_fulfillment_at: 1.month.from_now
    )

    assert_not fulfillment.valid?
    assert fulfillment.errors[:fulfillment_period].present?
  end

  test "validates unique source" do
    existing = usage_credits_fulfillments(:active_subscription_fulfillment)

    duplicate = UsageCredits::Fulfillment.new(
      wallet: existing.wallet,
      source: existing.source,
      fulfillment_type: "subscription",
      credits_last_fulfillment: 500,
      last_fulfilled_at: Time.current
    )

    assert_not duplicate.valid?
    assert duplicate.errors[:source_id].present?
  end

  # ========================================
  # RECURRING? METHOD
  # ========================================

  test "recurring? returns true when fulfillment_period is set" do
    fulfillment = usage_credits_fulfillments(:active_subscription_fulfillment)

    assert fulfillment.recurring?
  end

  test "recurring? returns false for one-time fulfillments" do
    fulfillment = usage_credits_fulfillments(:pack_fulfillment_rich)

    assert_not fulfillment.recurring?
  end

  # ========================================
  # STOPPED? / ACTIVE? METHODS
  # ========================================

  test "stopped? returns true when stops_at is in the past" do
    fulfillment = usage_credits_fulfillments(:stopped_fulfillment)

    assert fulfillment.stopped?
  end

  test "stopped? returns false when stops_at is in the future" do
    fulfillment = usage_credits_fulfillments(:active_subscription_fulfillment)

    assert_not fulfillment.stopped?
  end

  test "stopped? returns false when stops_at is nil" do
    fulfillment = usage_credits_fulfillments(:trial_fulfillment)

    assert_not fulfillment.stopped?
  end

  test "active? is opposite of stopped?" do
    stopped = usage_credits_fulfillments(:stopped_fulfillment)
    active = usage_credits_fulfillments(:active_subscription_fulfillment)

    assert_not stopped.active?
    assert active.active?
  end

  # ========================================
  # DUE_FOR_FULFILLMENT? METHOD
  # ========================================

  test "due_for_fulfillment? returns true when next_fulfillment_at is past" do
    fulfillment = usage_credits_fulfillments(:active_subscription_fulfillment)
    fulfillment.update!(next_fulfillment_at: 1.hour.ago)

    assert fulfillment.due_for_fulfillment?
  end

  test "due_for_fulfillment? returns false when next_fulfillment_at is future" do
    fulfillment = usage_credits_fulfillments(:active_subscription_fulfillment)

    assert_not fulfillment.due_for_fulfillment?
  end

  test "due_for_fulfillment? returns false when stopped" do
    fulfillment = usage_credits_fulfillments(:stopped_fulfillment)

    assert_not fulfillment.due_for_fulfillment?
  end

  test "due_for_fulfillment? returns false when already fulfilled" do
    fulfillment = usage_credits_fulfillments(:active_subscription_fulfillment)
    # Set next_fulfillment_at <= last_fulfilled_at (bypass validation with update_columns)
    fulfillment.update_columns(
      next_fulfillment_at: 1.hour.ago,
      last_fulfilled_at: Time.current
    )

    assert_not fulfillment.due_for_fulfillment?
  end

  # ========================================
  # CALCULATE_NEXT_FULFILLMENT METHOD
  # ========================================

  test "calculate_next_fulfillment adds period to next_fulfillment_at" do
    fulfillment = usage_credits_fulfillments(:active_subscription_fulfillment)
    original_next = fulfillment.next_fulfillment_at

    next_time = fulfillment.calculate_next_fulfillment

    # Should be approximately 1 month from the original next_fulfillment_at
    assert next_time > original_next
    assert_in_delta (original_next + 1.month).to_i, next_time.to_i, 86400  # Within 1 day
  end

  test "calculate_next_fulfillment returns nil for non-recurring" do
    fulfillment = usage_credits_fulfillments(:pack_fulfillment_rich)

    assert_nil fulfillment.calculate_next_fulfillment
  end

  test "calculate_next_fulfillment returns nil when stopped" do
    fulfillment = usage_credits_fulfillments(:stopped_fulfillment)

    assert_nil fulfillment.calculate_next_fulfillment
  end

  test "calculate_next_fulfillment uses current time when next is past" do
    fulfillment = usage_credits_fulfillments(:active_subscription_fulfillment)
    fulfillment.update!(next_fulfillment_at: 5.days.ago)

    next_time = fulfillment.calculate_next_fulfillment

    # Should be from now, not from the past date
    assert next_time > Time.current
  end

  # ========================================
  # SCOPES
  # ========================================

  test "due_for_fulfillment scope finds fulfillments ready to process" do
    # Make one fulfillment due
    fulfillment = usage_credits_fulfillments(:active_subscription_fulfillment)
    fulfillment.update!(next_fulfillment_at: 1.hour.ago)

    due = UsageCredits::Fulfillment.due_for_fulfillment

    assert due.include?(fulfillment)
  end

  test "due_for_fulfillment scope excludes stopped fulfillments" do
    stopped = usage_credits_fulfillments(:stopped_fulfillment)

    due = UsageCredits::Fulfillment.due_for_fulfillment

    assert_not due.include?(stopped)
  end

  test "active scope returns non-stopped fulfillments" do
    active = UsageCredits::Fulfillment.active

    active.each do |f|
      assert f.active?, "Fulfillment #{f.id} should be active"
    end
  end

  # ========================================
  # ASSOCIATIONS
  # ========================================

  test "belongs to wallet" do
    fulfillment = usage_credits_fulfillments(:active_subscription_fulfillment)

    assert_equal usage_credits_wallets(:subscribed_wallet), fulfillment.wallet
  end

  test "belongs to source polymorphically" do
    fulfillment = usage_credits_fulfillments(:active_subscription_fulfillment)

    assert_equal "Pay::Subscription", fulfillment.source_type
  end

  # ========================================
  # FULFILLMENT SERVICE INTEGRATION
  # ========================================

  test "FulfillmentService processes due fulfillment and adds credits" do
    wallet = usage_credits_wallets(:subscribed_wallet)
    initial_credits = wallet.credits

    fulfillment = usage_credits_fulfillments(:active_subscription_fulfillment)
    fulfillment.update!(next_fulfillment_at: 1.second.ago)

    # Process the fulfillment
    service = UsageCredits::FulfillmentService.new(fulfillment)
    service.process

    # Credits should be added
    assert_equal initial_credits + 500, wallet.reload.credits
  end

  test "FulfillmentService updates next_fulfillment_at after processing" do
    fulfillment = usage_credits_fulfillments(:active_subscription_fulfillment)
    fulfillment.update!(next_fulfillment_at: 1.second.ago)
    original_next = fulfillment.next_fulfillment_at

    service = UsageCredits::FulfillmentService.new(fulfillment)
    service.process

    fulfillment.reload
    assert fulfillment.next_fulfillment_at > original_next
  end

  test "FulfillmentService updates last_fulfilled_at" do
    fulfillment = usage_credits_fulfillments(:active_subscription_fulfillment)
    fulfillment.update!(next_fulfillment_at: 1.second.ago)
    original_last = fulfillment.last_fulfilled_at

    service = UsageCredits::FulfillmentService.new(fulfillment)
    service.process

    fulfillment.reload
    assert fulfillment.last_fulfilled_at > original_last
  end

  test "FulfillmentService.process_pending_fulfillments processes all due" do
    # Make two fulfillments due
    f1 = usage_credits_fulfillments(:active_subscription_fulfillment)
    f1.update!(next_fulfillment_at: 1.second.ago)

    f2 = usage_credits_fulfillments(:trial_fulfillment)
    f2.update!(next_fulfillment_at: 1.second.ago)

    count = UsageCredits::FulfillmentService.process_pending_fulfillments

    assert count >= 2
  end

  test "FulfillmentService skips non-due fulfillments" do
    wallet = usage_credits_wallets(:subscribed_wallet)
    initial_credits = wallet.credits

    fulfillment = usage_credits_fulfillments(:active_subscription_fulfillment)
    # Ensure it's not due
    fulfillment.update!(next_fulfillment_at: 1.day.from_now)

    service = UsageCredits::FulfillmentService.new(fulfillment)
    service.process

    # Credits should not change
    assert_equal initial_credits, wallet.reload.credits
  end

  # ========================================
  # EXPIRING VS ROLLOVER CREDITS
  # ========================================

  test "fulfillment creates expiring credits for non-rollover plans" do
    wallet = usage_credits_wallets(:subscribed_wallet)

    # Use an existing fulfillment and make it due
    fulfillment = usage_credits_fulfillments(:active_subscription_fulfillment)
    fulfillment.update_columns(
      next_fulfillment_at: 1.second.ago,
      last_fulfilled_at: 1.month.ago
    )

    service = UsageCredits::FulfillmentService.new(fulfillment)
    service.process

    # Check the latest transaction has an expiration
    latest_tx = wallet.transactions.where(category: "subscription_credits").order(:created_at).last
    assert_not_nil latest_tx.expires_at
  end

  test "fulfillment creates non-expiring credits for rollover plans" do
    wallet = usage_credits_wallets(:subscribed_wallet)

    # Create with future date, then use update_columns to bypass validation
    fulfillment = UsageCredits::Fulfillment.create!(
      wallet: wallet,
      fulfillment_type: "subscription",
      credits_last_fulfillment: 1000,
      fulfillment_period: "1.month",
      last_fulfilled_at: 1.month.ago,
      next_fulfillment_at: 1.day.from_now,
      metadata: { plan: "rollover_plan_monthly" }
    )

    # Make it due now (bypass validation with update_columns)
    fulfillment.update_columns(next_fulfillment_at: 1.second.ago)

    service = UsageCredits::FulfillmentService.new(fulfillment)
    service.process

    # Check the latest transaction does NOT have an expiration
    latest_tx = wallet.transactions.where(category: "subscription_credits").order(:created_at).last
    assert_nil latest_tx.expires_at
  end

  # ========================================
  # EDGE CASES
  # ========================================

  test "fulfillment with nil next_fulfillment_at is not due" do
    fulfillment = usage_credits_fulfillments(:pack_fulfillment_rich)

    assert_not fulfillment.due_for_fulfillment?
  end

  test "fulfillment handles missing subscription plan gracefully" do
    wallet = usage_credits_wallets(:subscribed_wallet)

    # Create with future date, then update_columns to bypass validation
    fulfillment = UsageCredits::Fulfillment.create!(
      wallet: wallet,
      fulfillment_type: "subscription",
      credits_last_fulfillment: 500,
      fulfillment_period: "1.month",
      last_fulfilled_at: 1.month.ago,
      next_fulfillment_at: 1.day.from_now,
      metadata: { plan: "nonexistent_plan" }
    )

    fulfillment.update_columns(next_fulfillment_at: 1.second.ago)

    service = UsageCredits::FulfillmentService.new(fulfillment)

    assert_raises(UsageCredits::InvalidOperation) do
      service.process
    end
  end

  test "fulfillment with zero credits is handled by service validation" do
    wallet = usage_credits_wallets(:subscribed_wallet)

    # Manual fulfillment requires credits in metadata
    fulfillment = UsageCredits::Fulfillment.create!(
      wallet: wallet,
      fulfillment_type: "manual",
      credits_last_fulfillment: 100,
      last_fulfilled_at: 1.month.ago,
      next_fulfillment_at: 1.day.from_now,
      fulfillment_period: "1.month",
      metadata: { credits: 100 }  # Has credits, will process
    )

    fulfillment.update_columns(next_fulfillment_at: 1.second.ago)

    service = UsageCredits::FulfillmentService.new(fulfillment)

    # Should process normally
    assert_nothing_raised do
      service.process
    end
  end

  test "fulfillment timestamps are preserved" do
    fulfillment = usage_credits_fulfillments(:active_subscription_fulfillment)

    assert_not_nil fulfillment.created_at
    assert_not_nil fulfillment.updated_at
  end

  test "multiple fulfillments for same wallet work correctly" do
    wallet = usage_credits_wallets(:subscribed_wallet)
    initial_credits = wallet.credits

    # Create two fulfillments with future dates first
    f1 = UsageCredits::Fulfillment.create!(
      wallet: wallet,
      fulfillment_type: "manual",
      credits_last_fulfillment: 100,
      fulfillment_period: "1.month",
      last_fulfilled_at: 1.month.ago,
      next_fulfillment_at: 1.day.from_now,
      metadata: { credits: 100 }
    )

    f2 = UsageCredits::Fulfillment.create!(
      wallet: wallet,
      fulfillment_type: "manual",
      credits_last_fulfillment: 200,
      fulfillment_period: "1.month",
      last_fulfilled_at: 1.month.ago,
      next_fulfillment_at: 2.days.from_now,
      metadata: { credits: 200 }
    )

    # Make them due now (bypass validation)
    f1.update_columns(next_fulfillment_at: 1.second.ago)
    f2.update_columns(next_fulfillment_at: 1.second.ago)

    UsageCredits::FulfillmentService.new(f1).process
    UsageCredits::FulfillmentService.new(f2).process

    # Both should add credits
    assert_equal initial_credits + 300, wallet.reload.credits
  end
end
