# frozen_string_literal: true

require "test_helper"

# ============================================================================
# PAY SUBSCRIPTION EXTENSION TEST SUITE
# ============================================================================
#
# This test suite tests the PaySubscriptionExtension concern that integrates
# the Pay gem with our UsageCredits system. The extension uses after_commit
# callbacks to:
#   1) Award initial credits (trial or first-cycle) when subscriptions are created
#   2) Create Fulfillment records for recurring credit awards
#   3) Update fulfillment on renewal and cancellation
#
# ## IMPORTANT: Fixture Wallet Usage
#
# When using fixture users, always use `user.credit_wallet` to get the existing
# fixture wallet instead of creating a new wallet. Creating a new wallet would
# result in TWO wallets for the same owner, causing tests to fail.
#
# For tests that need a truly fresh user/wallet, use:
#   user = User.create!(email: "unique@example.com", name: "Test User")
#   wallet = user.credit_wallet  # Auto-created by HasWallet concern
#
# ============================================================================

class PaySubscriptionExtensionTest < ActiveSupport::TestCase
  setup do
    # Configure test subscription plans
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

      config.subscription_plan :test_premium do
        processor_plan(:fake_processor, "premium_plan_monthly")
        gives 2000.credits.every(:month)
        signup_bonus 200.credits
        unused_credits :expire
      end
    end
  end

  teardown do
    UsageCredits.reset!
  end

  # ========================================
  # PLAN IDENTIFICATION
  # ========================================

  test "credit_subscription_plan finds matching plan by processor_id" do
    subscription = pay_subscriptions(:active_subscription)
    plan = subscription.credit_subscription_plan

    assert_not_nil plan
  end

  test "provides_credits? returns true when plan exists" do
    subscription = pay_subscriptions(:active_subscription)
    assert subscription.provides_credits?
  end

  test "provides_credits? returns false when no matching plan" do
    subscription = pay_subscriptions(:active_subscription)
    subscription.processor_plan = "unknown_plan_id"

    assert_not subscription.provides_credits?
  end

  # ========================================
  # INITIAL SUBSCRIPTION SETUP (ACTIVE)
  # ========================================

  test "active subscription creation awards initial credits" do
    # Create a fresh user to avoid fixture wallet conflicts
    user = User.create!(email: "sub_active@example.com", name: "Sub Active User")
    wallet = user.credit_wallet  # Auto-created wallet

    customer = Pay::Customer.create!(
      owner: user,
      processor: :fake_processor,
      processor_id: "cus_sub_active_test"
    )

    # 500 credits + 100 signup bonus = 600 total
    assert_difference -> { wallet.reload.credits }, 600 do
      Pay::Subscription.create!(
        customer: customer,
        name: "default",
        processor_id: "sub_active_test",
        processor_plan: "pro_plan_monthly",
        status: "active",
        quantity: 1
      )
    end
  end

  test "active subscription creates fulfillment record" do
    # Create a fresh user to avoid fixture wallet conflicts
    user = User.create!(email: "sub_fulfill@example.com", name: "Sub Fulfill User")
    user.credit_wallet  # Ensure wallet exists

    customer = Pay::Customer.create!(
      owner: user,
      processor: :fake_processor,
      processor_id: "cus_sub_fulfill_test"
    )

    assert_difference -> { UsageCredits::Fulfillment.count }, 1 do
      subscription = Pay::Subscription.create!(
        customer: customer,
        name: "default",
        processor_id: "sub_fulfill_test",
        processor_plan: "pro_plan_monthly",
        status: "active",
        quantity: 1
      )

      fulfillment = UsageCredits::Fulfillment.find_by(source: subscription)
      assert_not_nil fulfillment
      assert_equal "subscription", fulfillment.fulfillment_type
      assert_not_nil fulfillment.next_fulfillment_at
    end
  end

  test "active subscription awards signup bonus separately" do
    # Create a fresh user to avoid fixture wallet conflicts
    user = User.create!(email: "sub_bonus@example.com", name: "Sub Bonus User")
    wallet = user.credit_wallet  # Auto-created wallet

    customer = Pay::Customer.create!(
      owner: user,
      processor: :fake_processor,
      processor_id: "cus_sub_bonus_test"
    )

    Pay::Subscription.create!(
      customer: customer,
      name: "default",
      processor_id: "sub_bonus_test",
      processor_plan: "pro_plan_monthly",
      status: "active",
      quantity: 1
    )

    # Should have signup bonus transaction
    signup_bonus_tx = wallet.transactions.find_by(category: "subscription_signup_bonus")
    assert_not_nil signup_bonus_tx
    assert_equal 100, signup_bonus_tx.amount
  end

  test "active subscription awards first period credits" do
    # Create a fresh user to avoid fixture wallet conflicts
    user = User.create!(email: "sub_credits@example.com", name: "Sub Credits User")
    wallet = user.credit_wallet  # Auto-created wallet

    customer = Pay::Customer.create!(
      owner: user,
      processor: :fake_processor,
      processor_id: "cus_sub_credits_test"
    )

    Pay::Subscription.create!(
      customer: customer,
      name: "default",
      processor_id: "sub_credits_test",
      processor_plan: "pro_plan_monthly",
      status: "active",
      quantity: 1
    )

    # Should have subscription credits transaction
    sub_credit_tx = wallet.transactions.find_by(category: "subscription_credits")
    assert_not_nil sub_credit_tx
    assert_equal 500, sub_credit_tx.amount
  end

  test "active subscription sets credit expiration for non-rollover plans" do
    # Create a fresh user to avoid fixture wallet conflicts
    user = User.create!(email: "sub_expire@example.com", name: "Sub Expire User")
    wallet = user.credit_wallet  # Auto-created wallet

    customer = Pay::Customer.create!(
      owner: user,
      processor: :fake_processor,
      processor_id: "cus_sub_expire_test"
    )

    Pay::Subscription.create!(
      customer: customer,
      name: "default",
      processor_id: "sub_expire_test",
      processor_plan: "pro_plan_monthly",
      status: "active",
      quantity: 1
    )

    # Subscription credits should have expiration
    sub_credit_tx = wallet.transactions.find_by(category: "subscription_credits")
    assert_not_nil sub_credit_tx.expires_at
  end

  test "rollover subscription creates non-expiring credits" do
    # Create a fresh user to avoid fixture wallet conflicts
    user = User.create!(email: "sub_rollover@example.com", name: "Sub Rollover User")
    wallet = user.credit_wallet  # Auto-created wallet

    customer = Pay::Customer.create!(
      owner: user,
      processor: :fake_processor,
      processor_id: "cus_sub_rollover_test"
    )

    Pay::Subscription.create!(
      customer: customer,
      name: "default",
      processor_id: "sub_rollover_test",
      processor_plan: "rollover_plan_monthly",
      status: "active",
      quantity: 1
    )

    # Subscription credits should NOT have expiration
    sub_credit_tx = wallet.transactions.find_by(category: "subscription_credits")
    assert_nil sub_credit_tx.expires_at
  end

  # ========================================
  # TRIAL SUBSCRIPTION SETUP
  # ========================================

  test "trialing subscription awards trial credits" do
    # Create a fresh user to avoid fixture wallet conflicts
    user = User.create!(email: "sub_trial@example.com", name: "Sub Trial User")
    wallet = user.credit_wallet  # Auto-created wallet

    customer = Pay::Customer.create!(
      owner: user,
      processor: :fake_processor,
      processor_id: "cus_sub_trial_test"
    )

    trial_ends_at = 7.days.from_now

    # Trial only awards trial credits (50), not signup bonus or regular credits
    assert_difference -> { wallet.reload.credits }, 50 do
      Pay::Subscription.create!(
        customer: customer,
        name: "default",
        processor_id: "sub_trial_test",
        processor_plan: "pro_plan_monthly",
        status: "trialing",
        trial_ends_at: trial_ends_at,
        quantity: 1
      )
    end
  end

  test "trialing subscription sets trial credit expiration to trial_ends_at" do
    # Create a fresh user to avoid fixture wallet conflicts
    user = User.create!(email: "sub_trial_exp@example.com", name: "Sub Trial Exp User")
    wallet = user.credit_wallet  # Auto-created wallet

    customer = Pay::Customer.create!(
      owner: user,
      processor: :fake_processor,
      processor_id: "cus_sub_trial_exp_test"
    )

    trial_ends_at = 7.days.from_now

    Pay::Subscription.create!(
      customer: customer,
      name: "default",
      processor_id: "sub_trial_exp_test",
      processor_plan: "pro_plan_monthly",
      status: "trialing",
      trial_ends_at: trial_ends_at,
      quantity: 1
    )

    # Trial credits should expire when trial ends
    trial_tx = wallet.transactions.find_by(category: "subscription_trial")
    assert_not_nil trial_tx
    assert_equal trial_ends_at.to_i, trial_tx.expires_at.to_i
  end

  test "trialing subscription does not award signup bonus or regular credits" do
    # Create a fresh user to avoid fixture wallet conflicts
    user = User.create!(email: "sub_trial_only@example.com", name: "Sub Trial Only User")
    wallet = user.credit_wallet  # Auto-created wallet

    customer = Pay::Customer.create!(
      owner: user,
      processor: :fake_processor,
      processor_id: "cus_sub_trial_only_test"
    )

    Pay::Subscription.create!(
      customer: customer,
      name: "default",
      processor_id: "sub_trial_only_test",
      processor_plan: "pro_plan_monthly",
      status: "trialing",
      trial_ends_at: 7.days.from_now,
      quantity: 1
    )

    # Should NOT have signup bonus or subscription credits
    assert_nil wallet.transactions.find_by(category: "subscription_signup_bonus")
    assert_nil wallet.transactions.find_by(category: "subscription_credits")

    # Should ONLY have trial credits
    assert_not_nil wallet.transactions.find_by(category: "subscription_trial")
  end

  # ========================================
  # SUBSCRIPTION STATUS TRANSITIONS
  # ========================================

  test "incomplete subscription does not award credits" do
    # Create a fresh user to avoid fixture wallet conflicts
    user = User.create!(email: "sub_incomplete@example.com", name: "Sub Incomplete User")
    wallet = user.credit_wallet  # Auto-created wallet

    customer = Pay::Customer.create!(
      owner: user,
      processor: :fake_processor,
      processor_id: "cus_sub_incomplete_test"
    )

    # Create incomplete subscription (no credits awarded yet)
    assert_no_difference -> { wallet.reload.credits } do
      Pay::Subscription.create!(
        customer: customer,
        name: "default",
        processor_id: "sub_incomplete_test",
        processor_plan: "pro_plan_monthly",
        status: "incomplete",
        quantity: 1
      )
    end
  end

  test "incomplete to active transition awards credits" do
    # Create a fresh user to avoid fixture wallet conflicts
    user = User.create!(email: "sub_transition@example.com", name: "Sub Transition User")
    wallet = user.credit_wallet  # Auto-created wallet

    customer = Pay::Customer.create!(
      owner: user,
      processor: :fake_processor,
      processor_id: "cus_sub_transition_test"
    )

    # Create incomplete subscription (no credits awarded yet)
    subscription = Pay::Subscription.create!(
      customer: customer,
      name: "default",
      processor_id: "sub_transition_test",
      processor_plan: "pro_plan_monthly",
      status: "incomplete",
      quantity: 1
    )

    # No credits yet
    assert_equal 0, wallet.reload.credits

    # Transition to active - should now award credits
    assert_difference -> { wallet.reload.credits }, 600 do  # 500 + 100 signup bonus
      subscription.update!(status: "active")
    end
  end

  # ========================================
  # SUBSCRIPTION RENEWAL
  # ========================================

  test "subscription renewal extends fulfillment stops_at" do
    subscription = pay_subscriptions(:active_subscription)
    fulfillment = usage_credits_fulfillments(:active_subscription_fulfillment)

    original_stops_at = fulfillment.stops_at
    new_period_end = 90.days.from_now

    # Simulate renewal by updating current_period_end
    subscription.update!(current_period_end: new_period_end)

    # Fulfillment stops_at should be updated
    assert fulfillment.reload.stops_at > original_stops_at
  end

  test "subscription renewal updates fulfillment when ends_at changes" do
    subscription = pay_subscriptions(:active_subscription)
    fulfillment = usage_credits_fulfillments(:active_subscription_fulfillment)

    # Update ends_at to simulate renewal
    new_ends_at = 90.days.from_now
    subscription.update!(ends_at: new_ends_at, status: "active")

    fulfillment.reload

    # Fulfillment should be updated with new stops_at
    assert_not_nil fulfillment.stops_at
  end

  # ========================================
  # SUBSCRIPTION CANCELLATION
  # ========================================

  test "subscription cancellation stops fulfillment" do
    subscription = pay_subscriptions(:active_subscription)
    fulfillment = usage_credits_fulfillments(:active_subscription_fulfillment)

    # Cancel subscription
    cancellation_date = 1.day.from_now
    subscription.update!(status: "canceled", ends_at: cancellation_date)

    # Fulfillment should be stopped
    fulfillment.reload
    assert_not_nil fulfillment.stops_at
    assert fulfillment.stops_at <= cancellation_date + 1.day
  end

  test "canceled subscription has stopped fulfillment" do
    subscription = pay_subscriptions(:canceled_subscription)
    fulfillment = usage_credits_fulfillments(:stopped_fulfillment)

    assert_equal "canceled", subscription.status
    assert_not_nil fulfillment.stops_at
    assert fulfillment.stopped?
  end

  # ========================================
  # DOUBLE FULFILLMENT PREVENTION
  # ========================================

  test "duplicate subscription callback does not double-award credits" do
    # Create a fresh user to avoid fixture wallet conflicts
    user = User.create!(email: "sub_idempotent@example.com", name: "Sub Idempotent User")
    wallet = user.credit_wallet  # Auto-created wallet

    customer = Pay::Customer.create!(
      owner: user,
      processor: :fake_processor,
      processor_id: "cus_sub_idempotent_test"
    )

    # Create subscription
    subscription = Pay::Subscription.create!(
      customer: customer,
      name: "default",
      processor_id: "sub_idempotent_test",
      processor_plan: "pro_plan_monthly",
      status: "active",
      quantity: 1
    )

    # Manually trigger the callback again (simulating duplicate webhook)
    # The credits_already_fulfilled? check should prevent double-award
    assert_no_difference -> { wallet.reload.credits } do
      subscription.send(:handle_initial_award_and_fulfillment_setup)
    end
  end

  test "fulfillment record prevents duplicate credit awards" do
    subscription = pay_subscriptions(:active_subscription)
    wallet = subscription.customer.owner.credit_wallet

    initial_credit_count = wallet.credits

    # Fulfillment already exists, so re-running should not award again
    subscription.send(:handle_initial_award_and_fulfillment_setup)

    # No new credits awarded
    assert_equal initial_credit_count, wallet.reload.credits
  end

  # ========================================
  # EDGE CASES
  # ========================================

  test "subscription without matching plan does not award credits" do
    # Create a fresh user to avoid fixture wallet conflicts
    user = User.create!(email: "sub_no_plan@example.com", name: "Sub No Plan User")
    wallet = user.credit_wallet  # Auto-created wallet

    customer = Pay::Customer.create!(
      owner: user,
      processor: :fake_processor,
      processor_id: "cus_sub_no_plan_test"
    )

    # Create subscription with unknown plan
    assert_no_difference -> { wallet.reload.credits } do
      Pay::Subscription.create!(
        customer: customer,
        name: "default",
        processor_id: "sub_no_plan_test",
        processor_plan: "unknown_plan_id",
        status: "active",
        quantity: 1
      )
    end
  end

  test "subscription without owner wallet is handled gracefully" do
    # Create user and immediately destroy wallet to test "no wallet" scenario
    user = User.create!(email: "sub_no_wallet@example.com", name: "No Wallet Sub")
    user.credit_wallet.destroy!  # Destroy the auto-created wallet
    user.reload  # Clear association cache

    customer = Pay::Customer.create!(
      owner: user,
      processor: :fake_processor,
      processor_id: "cus_sub_no_wallet_test"
    )

    # Should not raise error even though user has no wallet
    assert_nothing_raised do
      Pay::Subscription.create!(
        customer: customer,
        name: "default",
        processor_id: "sub_no_wallet_test",
        processor_plan: "pro_plan_monthly",
        status: "active",
        quantity: 1
      )
    end
  end

  test "fulfillment has correct metadata" do
    subscription = pay_subscriptions(:active_subscription)
    fulfillment = usage_credits_fulfillments(:active_subscription_fulfillment)

    assert_equal subscription.id, fulfillment.metadata["subscription_id"]
    assert_not_nil fulfillment.metadata["plan"]
  end

  test "fulfillment period matches plan configuration" do
    fulfillment = usage_credits_fulfillments(:active_subscription_fulfillment)

    assert_equal "1.month", fulfillment.fulfillment_period
  end

  test "next_fulfillment_at is set in future for new subscription" do
    # Create a fresh user to avoid fixture wallet conflicts
    user = User.create!(email: "sub_future@example.com", name: "Sub Future User")
    user.credit_wallet  # Ensure wallet exists

    customer = Pay::Customer.create!(
      owner: user,
      processor: :fake_processor,
      processor_id: "cus_sub_future_test"
    )

    subscription = Pay::Subscription.create!(
      customer: customer,
      name: "default",
      processor_id: "sub_future_test",
      processor_plan: "pro_plan_monthly",
      status: "active",
      quantity: 1
    )

    fulfillment = UsageCredits::Fulfillment.find_by(source: subscription)

    assert_not_nil fulfillment
    assert_not_nil fulfillment.next_fulfillment_at
    assert fulfillment.next_fulfillment_at > Time.current
  end

  test "subscription transaction metadata includes plan information" do
    # Create a fresh user to avoid fixture wallet conflicts
    user = User.create!(email: "sub_metadata@example.com", name: "Sub Metadata User")
    wallet = user.credit_wallet  # Auto-created wallet

    customer = Pay::Customer.create!(
      owner: user,
      processor: :fake_processor,
      processor_id: "cus_sub_metadata_test"
    )

    Pay::Subscription.create!(
      customer: customer,
      name: "default",
      processor_id: "sub_metadata_test",
      processor_plan: "pro_plan_monthly",
      status: "active",
      quantity: 1
    )

    # Check that transactions have subscription metadata
    sub_tx = wallet.transactions.find_by(category: "subscription_credits")
    assert_not_nil sub_tx.metadata["subscription_id"]
    assert_not_nil sub_tx.metadata["plan"]
  end

  # ========================================
  # INTEGRATION WITH FIXTURES
  # ========================================

  test "active_subscription fixture has fulfillment" do
    subscription = pay_subscriptions(:active_subscription)
    fulfillment = usage_credits_fulfillments(:active_subscription_fulfillment)

    assert_equal subscription.id, fulfillment.source_id
    assert_equal "Pay::Subscription", fulfillment.source_type
  end

  test "trialing_subscription fixture has trial fulfillment" do
    subscription = pay_subscriptions(:trialing_subscription)
    fulfillment = usage_credits_fulfillments(:trial_fulfillment)

    assert_equal subscription.id, fulfillment.source_id
    assert fulfillment.metadata["trial"]
  end

  # ========================================
  # SUBSCRIPTION PLAN CHANGES
  # ========================================

  test "plan change updates fulfillment metadata" do
    # Create a fresh user with a pro subscription
    user = User.create!(email: "planchange@example.com", name: "Plan Change User")
    user.credit_wallet  # Ensure wallet exists

    customer = Pay::Customer.create!(
      owner: user,
      processor: :fake_processor,
      processor_id: "cus_planchange_test"
    )

    subscription = Pay::Subscription.create!(
      customer: customer,
      name: "default",
      processor_id: "sub_planchange_test",
      processor_plan: "pro_plan_monthly",  # Start with pro plan
      status: "active",
      quantity: 1
    )

    fulfillment = UsageCredits::Fulfillment.find_by(source: subscription)
    assert_equal "pro_plan_monthly", fulfillment.metadata["plan"]

    # Swap to premium plan
    subscription.update!(processor_plan: "premium_plan_monthly")

    # Fulfillment should now reference the new plan
    fulfillment.reload
    assert_equal "premium_plan_monthly", fulfillment.metadata["plan"]
  end
end
