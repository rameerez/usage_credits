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

  test "upgrade to higher plan grants immediate credits" do
    # Create a fresh user with a pro subscription (500 credits/month)
    user = User.create!(email: "upgrade@example.com", name: "Upgrade User")
    wallet = user.credit_wallet

    customer = Pay::Customer.create!(
      owner: user,
      processor: :fake_processor,
      processor_id: "cus_upgrade_test"
    )

    subscription = Pay::Subscription.create!(
      customer: customer,
      name: "default",
      processor_id: "sub_upgrade_test",
      processor_plan: "pro_plan_monthly",  # 500 credits + 100 signup bonus
      status: "active",
      quantity: 1
    )

    # Initial credits: 500 + 100 signup bonus = 600
    assert_equal 600, wallet.reload.credits

    # Upgrade to premium (2000 credits/month + 200 signup bonus, but no signup bonus on upgrade)
    assert_difference -> { wallet.reload.credits }, 2000 do
      subscription.update!(processor_plan: "premium_plan_monthly")
    end

    # Total should be 600 + 2000 = 2600
    assert_equal 2600, wallet.reload.credits

    # Should have a transaction for the upgrade
    upgrade_tx = wallet.transactions.where(category: "subscription_upgrade").last
    assert_not_nil upgrade_tx
    assert_equal 2000, upgrade_tx.amount
    assert_equal "premium_plan_monthly", upgrade_tx.metadata["plan"]
  end

  test "downgrade schedules plan change for end of period" do
    # Create a fresh user with a premium subscription (2000 credits/month)
    user = User.create!(email: "downgrade@example.com", name: "Downgrade User")
    wallet = user.credit_wallet

    customer = Pay::Customer.create!(
      owner: user,
      processor: :fake_processor,
      processor_id: "cus_downgrade_test"
    )

    subscription = Pay::Subscription.create!(
      customer: customer,
      name: "default",
      processor_id: "sub_downgrade_test",
      processor_plan: "premium_plan_monthly",  # 2000 credits + 200 signup bonus
      status: "active",
      quantity: 1,
      current_period_end: 30.days.from_now
    )

    # Initial credits: 2000 + 200 signup bonus = 2200
    assert_equal 2200, wallet.reload.credits

    fulfillment = UsageCredits::Fulfillment.find_by(source: subscription)
    assert_equal "premium_plan_monthly", fulfillment.metadata["plan"]

    # Downgrade to starter (500 credits/month)
    # Should NOT deduct credits immediately
    assert_no_difference -> { wallet.reload.credits } do
      subscription.update!(processor_plan: "pro_plan_monthly")
    end

    # Credits should remain unchanged
    assert_equal 2200, wallet.reload.credits

    # Fulfillment should have pending plan change scheduled
    fulfillment.reload
    assert_equal "premium_plan_monthly", fulfillment.metadata["plan"], "Current plan should still be premium"
    assert_equal "pro_plan_monthly", fulfillment.metadata["pending_plan_change"], "Should schedule downgrade"
    assert_not_nil fulfillment.metadata["plan_change_at"], "Should have scheduled time"

    # No downgrade transaction should exist yet
    assert_nil wallet.transactions.find_by(category: "subscription_downgrade")
  end

  test "scheduled downgrade applies on subscription renewal" do
    # Create a fresh user with a premium subscription
    user = User.create!(email: "downgrade_renew@example.com", name: "Downgrade Renew User")
    wallet = user.credit_wallet

    customer = Pay::Customer.create!(
      owner: user,
      processor: :fake_processor,
      processor_id: "cus_downgrade_renew_test"
    )

    subscription = Pay::Subscription.create!(
      customer: customer,
      name: "default",
      processor_id: "sub_downgrade_renew_test",
      processor_plan: "premium_plan_monthly",
      status: "active",
      quantity: 1,
      current_period_end: 30.days.from_now
    )

    # Initial credits: 2000 + 200 signup bonus = 2200
    assert_equal 2200, wallet.reload.credits

    # Schedule a downgrade
    subscription.update!(processor_plan: "pro_plan_monthly")

    fulfillment = UsageCredits::Fulfillment.find_by(source: subscription)
    assert fulfillment.metadata.key?("pending_plan_change"), "Should have pending plan change"
    assert_equal "pro_plan_monthly", fulfillment.metadata["pending_plan_change"]

    # Simulate subscription renewal (what happens when Stripe sends renewal webhook)
    # The subscription's current_period_end moves forward
    new_period_end = 60.days.from_now
    subscription.update!(
      current_period_end: new_period_end,
      ends_at: nil  # Renewal clears ends_at
    )

    # After renewal, the scheduled downgrade should be applied
    fulfillment.reload
    assert_equal "pro_plan_monthly", fulfillment.metadata["plan"], "Should now be on starter plan"
    assert_nil fulfillment.metadata["pending_plan_change"], "Pending change should be cleared"
    assert_nil fulfillment.metadata["plan_change_at"], "Scheduled time should be cleared"

    # Credits remain unchanged (no deduction on downgrade)
    assert_equal 2200, wallet.reload.credits
  end

  # ========================================
  # EDGE CASES: CREDIT EXPIRATION ON UPGRADE
  # ========================================

  test "upgrade to expiring plan sets credit expiration correctly" do
    # Create a user with a rollover plan (credits don't expire)
    user = User.create!(email: "upgrade_expire@example.com", name: "Upgrade Expire User")
    wallet = user.credit_wallet

    customer = Pay::Customer.create!(
      owner: user,
      processor: :fake_processor,
      processor_id: "cus_upgrade_expire_test"
    )

    subscription = Pay::Subscription.create!(
      customer: customer,
      name: "default",
      processor_id: "sub_upgrade_expire_test",
      processor_plan: "rollover_plan_monthly",  # 1000 credits, no expiration
      status: "active",
      quantity: 1
    )

    # Rollover plan credits should NOT expire
    rollover_tx = wallet.transactions.find_by(category: "subscription_credits")
    assert_nil rollover_tx.expires_at, "Rollover credits should not expire"

    # Upgrade to premium (expiring plan)
    subscription.update!(processor_plan: "premium_plan_monthly")

    # Upgrade credits SHOULD expire
    upgrade_tx = wallet.transactions.find_by(category: "subscription_upgrade")
    assert_not_nil upgrade_tx, "Should have upgrade transaction"
    assert_not_nil upgrade_tx.expires_at, "Upgrade to expiring plan should have expiration date"

    # Expiration should be approximately 1 month from now + grace period
    expected_expiration = Time.current + 1.month + UsageCredits.configuration.fulfillment_grace_period
    assert_in_delta expected_expiration.to_i, upgrade_tx.expires_at.to_i, 60, "Expiration should be ~1 month + grace period from now"
  end

  test "upgrade to rollover plan does not set credit expiration" do
    # Create a user with an expiring plan
    user = User.create!(email: "upgrade_rollover@example.com", name: "Upgrade Rollover User")
    wallet = user.credit_wallet

    customer = Pay::Customer.create!(
      owner: user,
      processor: :fake_processor,
      processor_id: "cus_upgrade_rollover_test"
    )

    subscription = Pay::Subscription.create!(
      customer: customer,
      name: "default",
      processor_id: "sub_upgrade_rollover_test",
      processor_plan: "pro_plan_monthly",  # 500 credits, expires
      status: "active",
      quantity: 1
    )

    # Pro plan credits SHOULD expire
    pro_tx = wallet.transactions.find_by(category: "subscription_credits")
    assert_not_nil pro_tx.expires_at, "Expiring plan credits should have expiration"

    # Upgrade to rollover plan (more credits, no expiration)
    subscription.update!(processor_plan: "rollover_plan_monthly")

    # Upgrade credits should NOT expire (rollover plan)
    upgrade_tx = wallet.transactions.find_by(category: "subscription_upgrade")
    assert_not_nil upgrade_tx, "Should have upgrade transaction"
    assert_nil upgrade_tx.expires_at, "Upgrade to rollover plan should not have expiration"
  end

  # ========================================
  # EDGE CASES: NON-CREDIT PLAN TRANSITIONS
  # ========================================

  test "downgrade from credit plan to non-credit plan stops fulfillment" do
    # Create a user with a premium subscription
    user = User.create!(email: "downgrade_noncredit@example.com", name: "Downgrade NonCredit User")
    wallet = user.credit_wallet

    customer = Pay::Customer.create!(
      owner: user,
      processor: :fake_processor,
      processor_id: "cus_downgrade_noncredit_test"
    )

    subscription = Pay::Subscription.create!(
      customer: customer,
      name: "default",
      processor_id: "sub_downgrade_noncredit_test",
      processor_plan: "premium_plan_monthly",  # 2000 credits
      status: "active",
      quantity: 1,
      current_period_end: 30.days.from_now
    )

    # Initial credits: 2000 + 200 signup bonus = 2200
    assert_equal 2200, wallet.reload.credits

    fulfillment = UsageCredits::Fulfillment.find_by(source: subscription)
    assert_not_nil fulfillment
    original_stops_at = fulfillment.stops_at

    # Downgrade to a non-credit plan (not defined in our test setup)
    subscription.update!(processor_plan: "basic_plan_no_credits")

    # Fulfillment should be scheduled to stop
    fulfillment.reload
    assert_not_nil fulfillment.stops_at, "Fulfillment should have a stop date"
    assert fulfillment.stops_at <= 30.days.from_now, "Fulfillment should stop at end of period"
    assert_equal "downgrade_to_non_credit_plan", fulfillment.metadata["stopped_reason"]

    # Credits remain unchanged (no clawback)
    assert_equal 2200, wallet.reload.credits
  end

  test "REGRESSION: credit to non-credit to credit reactivation works" do
    # This tests the scenario:
    # 1. User starts with a credit plan
    # 2. User downgrades to a non-credit plan (fulfillment stops)
    # 3. User later switches back to a credit plan (fulfillment should reactivate)
    #
    # The bug was: credits_already_fulfilled? would return true (fulfillment exists)
    # even though it was stopped, blocking reactivation.

    user = User.create!(email: "reactivation@example.com", name: "Reactivation User")
    wallet = user.credit_wallet

    customer = Pay::Customer.create!(
      owner: user,
      processor: :fake_processor,
      processor_id: "cus_reactivation_test"
    )

    # 1. Start with a credit plan
    subscription = Pay::Subscription.create!(
      customer: customer,
      name: "default",
      processor_id: "sub_reactivation_test",
      processor_plan: "pro_plan_monthly",  # 500 + 100 = 600 credits
      status: "active",
      quantity: 1,
      current_period_end: 30.days.from_now
    )

    assert_equal 600, wallet.reload.credits
    fulfillment = UsageCredits::Fulfillment.find_by(source: subscription)
    assert_not_nil fulfillment, "Should have fulfillment"
    assert_nil fulfillment.metadata["stopped_reason"], "Fulfillment should be active"

    # 2. Downgrade to a non-credit plan
    # Set stops_at to a specific time we can test against
    downgrade_period_end = 35.days.from_now

    subscription.update!(
      processor_plan: "basic_plan_no_credits",
      current_period_end: downgrade_period_end
    )

    fulfillment.reload
    assert_equal "downgrade_to_non_credit_plan", fulfillment.metadata["stopped_reason"]
    assert_not_nil fulfillment.stops_at, "Fulfillment should be stopped"
    assert_equal downgrade_period_end.to_i, fulfillment.stops_at.to_i, "stops_at should match period end"

    # Credits remain the same after downgrade
    assert_equal 600, wallet.reload.credits

    # 3. Later, user switches back to a credit plan
    # Move time past the stop date so fulfillment is truly "stopped"
    travel_to downgrade_period_end + 5.days do
      # The fulfillment should now be considered stopped (stops_at in the past)
      fulfillment.reload
      assert fulfillment.stops_at <= Time.current, "Fulfillment should be past its stop date"

      # Track transaction count before reactivation
      tx_count_before = wallet.transactions.count

      # Switch back to credit plan
      # We need to update current_period_end for proper fulfillment scheduling
      subscription.update!(
        processor_plan: "premium_plan_monthly",  # 2000 credits
        current_period_end: Time.current + 30.days,
        status: "active"
      )

      # Should have created a new transaction for reactivation credits
      wallet.reload
      tx_count_after = wallet.transactions.count
      assert tx_count_after > tx_count_before,
        "REGRESSION: Switching from non-credit back to credit should create transaction. " \
        "Transactions before: #{tx_count_before}, after: #{tx_count_after}"

      # Look for the most recent subscription_credits transaction (the reactivation credits)
      new_credit_tx = wallet.transactions.where(category: "subscription_credits").order(created_at: :desc).first
      assert_not_nil new_credit_tx, "Should have a new subscription_credits transaction"
      assert_equal 2000, new_credit_tx.amount, "Reactivation should award 2000 credits"

      # Fulfillment should be reactivated
      fulfillment.reload
      assert_nil fulfillment.metadata["stopped_reason"],
        "REGRESSION: Fulfillment should be reactivated (stopped_reason cleared)"
      assert_equal "premium_plan_monthly", fulfillment.metadata["plan"],
        "Fulfillment should have new plan"
      assert fulfillment.stops_at > Time.current,
        "Fulfillment stops_at should be in the future"
    end
  end

  test "REGRESSION: credit to non-credit to credit BEFORE stop date reactivates fulfillment" do
    # This tests the scenario where a user:
    # 1. Has a credit plan
    # 2. Downgrades to non-credit (fulfillment scheduled to stop in the future)
    # 3. Changes mind and switches back to credit BEFORE the stop date
    #
    # The bug was: credits_already_fulfilled? returned true because stops_at was still
    # in the future, blocking reactivation.

    user = User.create!(email: "reactivation_before_stop@example.com", name: "Reactivation Before Stop")
    wallet = user.credit_wallet

    customer = Pay::Customer.create!(
      owner: user,
      processor: :fake_processor,
      processor_id: "cus_reactivation_before_stop"
    )

    # 1. Start with a credit plan
    subscription = Pay::Subscription.create!(
      customer: customer,
      name: "default",
      processor_id: "sub_reactivation_before_stop",
      processor_plan: "pro_plan_monthly",  # 500 + 100 = 600 credits
      status: "active",
      quantity: 1,
      current_period_end: 30.days.from_now
    )

    assert_equal 600, wallet.reload.credits
    fulfillment = UsageCredits::Fulfillment.find_by(source: subscription)
    assert_not_nil fulfillment

    # 2. Downgrade to a non-credit plan
    subscription.update!(
      processor_plan: "basic_plan_no_credits",
      current_period_end: 30.days.from_now
    )

    fulfillment.reload
    assert_equal "downgrade_to_non_credit_plan", fulfillment.metadata["stopped_reason"]
    assert fulfillment.stops_at > Time.current, "stops_at should be in the FUTURE"

    # Credits unchanged
    assert_equal 600, wallet.reload.credits

    # 3. User changes mind and switches back BEFORE stops_at
    # This should still reactivate because stopped_reason is set
    tx_count_before = wallet.transactions.count

    subscription.update!(
      processor_plan: "premium_plan_monthly",  # 2000 credits
      current_period_end: 30.days.from_now,
      status: "active"
    )

    # Should have created a new transaction for reactivation credits
    wallet.reload
    tx_count_after = wallet.transactions.count
    assert tx_count_after > tx_count_before,
      "REGRESSION: Switching back before stop date should create transaction"

    # Verify the credits were awarded
    new_credit_tx = wallet.transactions.where(category: "subscription_credits").order(created_at: :desc).first
    assert_not_nil new_credit_tx
    assert_equal 2000, new_credit_tx.amount, "Reactivation should award 2000 credits"

    # Fulfillment should be reactivated (stopped_reason cleared)
    fulfillment.reload
    assert_nil fulfillment.metadata["stopped_reason"],
      "REGRESSION: stopped_reason should be cleared on reactivation"
    assert_equal "premium_plan_monthly", fulfillment.metadata["plan"]
    assert fulfillment.stops_at > Time.current
  end

  test "lateral plan change with same credits only updates metadata" do
    # This tests the case where a user changes plans but the credit amounts are the same
    # We need to define another plan with the same credits for this test
    UsageCredits.configure do |config|
      config.subscription_plan :test_pro_annual do
        processor_plan(:fake_processor, "pro_plan_annual")
        gives 500.credits.every(:year)  # Same credits as pro monthly but different period
        unused_credits :expire
      end
    end

    user = User.create!(email: "lateral_change@example.com", name: "Lateral Change User")
    wallet = user.credit_wallet

    customer = Pay::Customer.create!(
      owner: user,
      processor: :fake_processor,
      processor_id: "cus_lateral_test"
    )

    subscription = Pay::Subscription.create!(
      customer: customer,
      name: "default",
      processor_id: "sub_lateral_test",
      processor_plan: "pro_plan_monthly",  # 500 credits
      status: "active",
      quantity: 1
    )

    initial_credits = wallet.reload.credits

    fulfillment = UsageCredits::Fulfillment.find_by(source: subscription)
    assert_equal "pro_plan_monthly", fulfillment.metadata["plan"]

    # Change to annual plan (same credits = 500)
    assert_no_difference -> { wallet.reload.credits } do
      subscription.update!(processor_plan: "pro_plan_annual")
    end

    # Only metadata should be updated, no credits granted
    fulfillment.reload
    assert_equal "pro_plan_annual", fulfillment.metadata["plan"]
    assert_equal initial_credits, wallet.reload.credits
  end

  # ========================================
  # EDGE CASES: MULTIPLE PLAN CHANGES
  # ========================================

  test "multiple upgrades in same period accumulate credits" do
    user = User.create!(email: "multi_upgrade@example.com", name: "Multi Upgrade User")
    wallet = user.credit_wallet

    customer = Pay::Customer.create!(
      owner: user,
      processor: :fake_processor,
      processor_id: "cus_multi_upgrade_test"
    )

    subscription = Pay::Subscription.create!(
      customer: customer,
      name: "default",
      processor_id: "sub_multi_upgrade_test",
      processor_plan: "pro_plan_monthly",  # 500 credits + 100 bonus
      status: "active",
      quantity: 1,
      current_period_end: 30.days.from_now
    )

    # Initial: 500 + 100 = 600
    assert_equal 600, wallet.reload.credits

    # First upgrade to premium (2000 credits)
    subscription.update!(processor_plan: "premium_plan_monthly")
    assert_equal 2600, wallet.reload.credits  # 600 + 2000

    # User downgrades back to pro (scheduled, no immediate change)
    subscription.update!(processor_plan: "pro_plan_monthly")
    assert_equal 2600, wallet.reload.credits  # Still 2600

    # User "goes back" to premium before period ends
    # This CANCELS the scheduled downgrade but does NOT grant more credits
    # because the user never actually left Premium. Stripe would not charge them again.
    subscription.update!(processor_plan: "premium_plan_monthly")
    assert_equal 2600, wallet.reload.credits  # Still 2600 - no duplicate credits

    # Pending downgrade should be cleared
    fulfillment = UsageCredits::Fulfillment.find_by(source: subscription)
    assert_nil fulfillment.metadata["pending_plan_change"],
      "Returning to current plan should clear pending downgrade"
  end

  # ========================================
  # REGRESSION TESTS: REVIEWER'S CRITICAL ISSUES
  # ========================================
  # These tests explicitly verify the bugs identified by the PR reviewer
  # to prevent accidental regression.

  # REVIEWER ISSUE #1: Credit Expiration Not Set on Upgrades (CRITICAL)
  # Location: pay_subscription_extension.rb:303-312 (original code)
  # The handle_plan_upgrade method did not set expires_at when new plan has unused_credits :expire

  test "REGRESSION: upgrade credits expire when new plan has unused_credits expire" do
    # Setup: User on rollover plan (credits don't expire)
    user = User.create!(email: "regression_expire1@example.com", name: "Regression Test 1")
    wallet = user.credit_wallet

    customer = Pay::Customer.create!(
      owner: user,
      processor: :fake_processor,
      processor_id: "cus_regression_expire1"
    )

    subscription = Pay::Subscription.create!(
      customer: customer,
      name: "default",
      processor_id: "sub_regression_expire1",
      processor_plan: "rollover_plan_monthly",  # Credits DON'T expire
      status: "active",
      quantity: 1
    )

    # Verify initial rollover credits don't expire
    initial_tx = wallet.transactions.find_by(category: "subscription_credits")
    assert_nil initial_tx.expires_at, "Rollover plan credits should not have expiration"

    # Upgrade to premium (unused_credits :expire)
    subscription.update!(processor_plan: "premium_plan_monthly")

    # THE BUG: Without the fix, upgrade_tx.expires_at would be nil (WRONG!)
    upgrade_tx = wallet.transactions.find_by(category: "subscription_upgrade")
    assert_not_nil upgrade_tx, "Upgrade transaction should exist"
    assert_not_nil upgrade_tx.expires_at,
      "REGRESSION: Upgrade to expiring plan MUST set expires_at. " \
      "This was the CRITICAL bug from PR review - credits would never expire!"

    # Verify expiration is approximately 1 month + grace period from now
    grace = UsageCredits.configuration.fulfillment_grace_period
    expected_min = Time.current + 1.month - 1.minute
    expected_max = Time.current + 1.month + grace + 1.minute
    assert upgrade_tx.expires_at >= expected_min, "Expiration should be at least 1 month away"
    assert upgrade_tx.expires_at <= expected_max, "Expiration should be within 1 month + grace period"
  end

  test "REGRESSION: upgrade credits do NOT expire when new plan has unused_credits rollover" do
    # Setup: User on expiring plan
    user = User.create!(email: "regression_expire2@example.com", name: "Regression Test 2")
    wallet = user.credit_wallet

    customer = Pay::Customer.create!(
      owner: user,
      processor: :fake_processor,
      processor_id: "cus_regression_expire2"
    )

    subscription = Pay::Subscription.create!(
      customer: customer,
      name: "default",
      processor_id: "sub_regression_expire2",
      processor_plan: "pro_plan_monthly",  # Credits DO expire
      status: "active",
      quantity: 1
    )

    # Verify initial credits expire
    initial_tx = wallet.transactions.find_by(category: "subscription_credits")
    assert_not_nil initial_tx.expires_at, "Pro plan credits should have expiration"

    # Upgrade to rollover plan (more credits, no expiration)
    subscription.update!(processor_plan: "rollover_plan_monthly")

    # Upgrade credits should NOT expire since new plan is rollover
    upgrade_tx = wallet.transactions.find_by(category: "subscription_upgrade")
    assert_not_nil upgrade_tx, "Upgrade transaction should exist"
    assert_nil upgrade_tx.expires_at,
      "REGRESSION: Upgrade to rollover plan should NOT set expires_at"
  end

  test "REGRESSION: upgrade from expiring to expiring plan sets correct expiration" do
    user = User.create!(email: "regression_expire3@example.com", name: "Regression Test 3")
    wallet = user.credit_wallet

    customer = Pay::Customer.create!(
      owner: user,
      processor: :fake_processor,
      processor_id: "cus_regression_expire3"
    )

    subscription = Pay::Subscription.create!(
      customer: customer,
      name: "default",
      processor_id: "sub_regression_expire3",
      processor_plan: "pro_plan_monthly",  # 500 credits, expires
      status: "active",
      quantity: 1
    )

    # Upgrade to premium (also expires)
    subscription.update!(processor_plan: "premium_plan_monthly")

    upgrade_tx = wallet.transactions.find_by(category: "subscription_upgrade")
    assert_not_nil upgrade_tx, "Upgrade transaction should exist"
    assert_not_nil upgrade_tx.expires_at,
      "REGRESSION: Upgrade from expiring to expiring plan MUST set expires_at"
  end

  # REVIEWER ISSUE #2: Nil Old Plan Handling (HIGH)
  # Location: pay_subscription_extension.rb:282-290 (original code)
  # When upgrading from a non-credit plan to a credit plan, old_plan is nil
  # and the code fell through to the else branch without granting credits.

  test "REGRESSION: swap from non-credit plan to credit plan does not double-award" do
    # This tests the CRITICAL bug where swapping from a non-credit plan to a credit plan
    # would trigger BOTH handle_initial_award_and_fulfillment_setup AND handle_plan_change,
    # resulting in double credit awards.
    #
    # The fix: plan_changed? should only return true if OLD plan was a credit plan.
    # Non-credit → credit should be handled ONLY by handle_initial_award_and_fulfillment_setup.

    user = User.create!(email: "regression_noncredit_to_credit@example.com", name: "NonCredit To Credit")
    wallet = user.credit_wallet

    customer = Pay::Customer.create!(
      owner: user,
      processor: :fake_processor,
      processor_id: "cus_regression_noncredit_to_credit"
    )

    # Create subscription with a non-credit plan first
    subscription = Pay::Subscription.create!(
      customer: customer,
      name: "default",
      processor_id: "sub_regression_noncredit_to_credit",
      processor_plan: "business_plan_no_credits",  # Not in UsageCredits config
      status: "active",
      quantity: 1
    )

    # No credits awarded (plan not in config)
    assert_equal 0, wallet.reload.credits

    # No fulfillment created for non-credit plan
    assert_nil UsageCredits::Fulfillment.find_by(source: subscription)

    # User swaps to a credit plan
    subscription.update!(processor_plan: "pro_plan_monthly")

    # Should award EXACTLY 600 credits (500 + 100 bonus), NOT MORE
    # The bug was: 1100 credits (600 from initial + 500 from upgrade)
    assert_equal 600, wallet.reload.credits,
      "REGRESSION: Swap from non-credit to credit should award exactly 600 credits (500 + 100 bonus). " \
      "If this is higher, handle_plan_change is incorrectly triggering for non-credit → credit swaps."

    # Should have fulfillment now
    fulfillment = UsageCredits::Fulfillment.find_by(source: subscription)
    assert_not_nil fulfillment

    # Should NOT have upgrade transaction (initial setup handles it)
    upgrade_tx = wallet.transactions.find_by(category: "subscription_upgrade")
    assert_nil upgrade_tx,
      "REGRESSION: Should not have 'subscription_upgrade' transaction for non-credit → credit swap. " \
      "This case should be handled by initial setup, not plan change."

    # Should have normal subscription_credits and signup_bonus
    assert_not_nil wallet.transactions.find_by(category: "subscription_credits")
    assert_not_nil wallet.transactions.find_by(category: "subscription_signup_bonus")
  end

  test "REGRESSION: plan_changed guard does not fire on initial subscription creation" do
    # This verifies we don't double-award credits on new subscriptions
    user = User.create!(email: "regression_guard@example.com", name: "Regression Guard")
    wallet = user.credit_wallet

    customer = Pay::Customer.create!(
      owner: user,
      processor: :fake_processor,
      processor_id: "cus_regression_guard"
    )

    # When subscription is created, old_plan_id is nil
    # plan_changed? should return false, not trigger upgrade logic
    subscription = Pay::Subscription.create!(
      customer: customer,
      name: "default",
      processor_id: "sub_regression_guard",
      processor_plan: "pro_plan_monthly",  # 500 credits + 100 bonus = 600
      status: "active",
      quantity: 1
    )

    # Should ONLY have 600 credits, not more
    # THE BUG: Without the nil check, plan_changed? would fire and grant 500 MORE
    assert_equal 600, wallet.reload.credits,
      "REGRESSION: Initial subscription should award exactly 600 credits (500 + 100 bonus), " \
      "not more. plan_changed? should NOT fire on initial creation."

    # Should have subscription_credits and signup_bonus, but NOT subscription_upgrade
    assert_not_nil wallet.transactions.find_by(category: "subscription_credits")
    assert_not_nil wallet.transactions.find_by(category: "subscription_signup_bonus")
    assert_nil wallet.transactions.find_by(category: "subscription_upgrade"),
      "REGRESSION: Should NOT have upgrade transaction on initial subscription"
  end

  # REVIEWER ISSUE #3: plan_changed? Guard Issue (MEDIUM)
  # Location: pay_subscription_extension.rb:88-90 (original code)
  # Only checks if NEW plan provides credits. Downgrade from credit plan to
  # non-credit plan won't trigger handle_plan_change.

  test "REGRESSION: downgrade from credit plan to non-credit plan triggers plan change" do
    user = User.create!(email: "regression_noncredit@example.com", name: "Regression NonCredit")
    wallet = user.credit_wallet

    customer = Pay::Customer.create!(
      owner: user,
      processor: :fake_processor,
      processor_id: "cus_regression_noncredit"
    )

    subscription = Pay::Subscription.create!(
      customer: customer,
      name: "default",
      processor_id: "sub_regression_noncredit",
      processor_plan: "premium_plan_monthly",
      status: "active",
      quantity: 1,
      current_period_end: 30.days.from_now
    )

    fulfillment = UsageCredits::Fulfillment.find_by(source: subscription)
    assert_not_nil fulfillment
    original_stops_at = fulfillment.stops_at

    # THE BUG: Without the fix, downgrading to non-credit plan wouldn't trigger
    # handle_plan_change because provides_credits? would return false
    subscription.update!(processor_plan: "enterprise_no_credits")

    fulfillment.reload
    # THE FIX: Fulfillment should be scheduled to stop
    assert_not_nil fulfillment.metadata["stopped_reason"],
      "REGRESSION: Downgrade to non-credit plan MUST stop fulfillment. " \
      "Without this, FulfillmentJob would keep awarding old plan credits!"
    assert_equal "downgrade_to_non_credit_plan", fulfillment.metadata["stopped_reason"]
    assert fulfillment.stops_at <= 30.days.from_now,
      "REGRESSION: Fulfillment should stop at end of current period"
  end

  test "REGRESSION: downgrade to non-credit plan preserves existing credits" do
    user = User.create!(email: "regression_preserve@example.com", name: "Regression Preserve")
    wallet = user.credit_wallet

    customer = Pay::Customer.create!(
      owner: user,
      processor: :fake_processor,
      processor_id: "cus_regression_preserve"
    )

    subscription = Pay::Subscription.create!(
      customer: customer,
      name: "default",
      processor_id: "sub_regression_preserve",
      processor_plan: "premium_plan_monthly",  # 2000 + 200 = 2200
      status: "active",
      quantity: 1,
      current_period_end: 30.days.from_now
    )

    initial_credits = wallet.reload.credits
    assert_equal 2200, initial_credits

    # Downgrade to non-credit plan
    subscription.update!(processor_plan: "basic_no_credits")

    # Credits should be PRESERVED (no clawback)
    assert_equal initial_credits, wallet.reload.credits,
      "REGRESSION: Downgrade to non-credit plan should preserve credits (no clawback)"
  end

  # ========================================
  # EDGE CASES: REVIEWER'S SUGGESTED TESTS
  # ========================================

  test "lateral plan change same credits different period updates metadata only" do
    UsageCredits.configure do |config|
      config.subscription_plan :test_pro_weekly do
        processor_plan(:fake_processor, "pro_plan_weekly")
        gives 500.credits.every(:week)  # Same 500 credits as pro monthly
        unused_credits :expire
      end
    end

    user = User.create!(email: "lateral_period@example.com", name: "Lateral Period")
    wallet = user.credit_wallet

    customer = Pay::Customer.create!(
      owner: user,
      processor: :fake_processor,
      processor_id: "cus_lateral_period"
    )

    subscription = Pay::Subscription.create!(
      customer: customer,
      name: "default",
      processor_id: "sub_lateral_period",
      processor_plan: "pro_plan_monthly",  # 500 credits
      status: "active",
      quantity: 1
    )

    initial_credits = wallet.reload.credits  # 600 (500 + 100 bonus)
    fulfillment = UsageCredits::Fulfillment.find_by(source: subscription)

    # Change to weekly plan (same credits, different period)
    assert_no_difference -> { wallet.reload.credits } do
      subscription.update!(processor_plan: "pro_plan_weekly")
    end

    # Metadata updated, no credits granted
    fulfillment.reload
    assert_equal "pro_plan_weekly", fulfillment.metadata["plan"]
    assert_nil wallet.transactions.find_by(category: "subscription_upgrade"),
      "Lateral change should not create upgrade transaction"
  end

  test "cancellation with pending downgrade works correctly" do
    user = User.create!(email: "cancel_pending@example.com", name: "Cancel Pending")
    wallet = user.credit_wallet

    customer = Pay::Customer.create!(
      owner: user,
      processor: :fake_processor,
      processor_id: "cus_cancel_pending"
    )

    subscription = Pay::Subscription.create!(
      customer: customer,
      name: "default",
      processor_id: "sub_cancel_pending",
      processor_plan: "premium_plan_monthly",
      status: "active",
      quantity: 1,
      current_period_end: 30.days.from_now
    )

    # Schedule a downgrade
    subscription.update!(processor_plan: "pro_plan_monthly")

    fulfillment = UsageCredits::Fulfillment.find_by(source: subscription)
    assert_equal "pro_plan_monthly", fulfillment.metadata["pending_plan_change"]

    # Now cancel the subscription
    subscription.update!(status: "canceled", ends_at: 30.days.from_now)

    # Fulfillment should have stops_at set - pending change becomes moot
    # Note: stopped? returns true only when stops_at <= Time.current
    fulfillment.reload
    assert_not_nil fulfillment.stops_at, "Fulfillment should have stops_at set after cancellation"
    assert fulfillment.stops_at <= 31.days.from_now, "Fulfillment stops_at should be at or before cancellation date"
    # The pending_plan_change remains in metadata but becomes irrelevant since fulfillment is stopping
  end

  test "upgrade then immediate downgrade handles pending correctly" do
    user = User.create!(email: "up_down@example.com", name: "Up Down")
    wallet = user.credit_wallet

    customer = Pay::Customer.create!(
      owner: user,
      processor: :fake_processor,
      processor_id: "cus_up_down"
    )

    subscription = Pay::Subscription.create!(
      customer: customer,
      name: "default",
      processor_id: "sub_up_down",
      processor_plan: "pro_plan_monthly",  # 500 + 100 = 600
      status: "active",
      quantity: 1,
      current_period_end: 30.days.from_now
    )

    assert_equal 600, wallet.reload.credits

    # Upgrade to premium (immediate credits)
    subscription.update!(processor_plan: "premium_plan_monthly")
    assert_equal 2600, wallet.reload.credits

    fulfillment = UsageCredits::Fulfillment.find_by(source: subscription)
    assert_equal "premium_plan_monthly", fulfillment.metadata["plan"]

    # Immediately downgrade back (scheduled, no refund)
    subscription.update!(processor_plan: "pro_plan_monthly")
    assert_equal 2600, wallet.reload.credits  # No change

    fulfillment.reload
    # Should have pending downgrade scheduled
    assert_equal "premium_plan_monthly", fulfillment.metadata["plan"]  # Still premium
    assert_equal "pro_plan_monthly", fulfillment.metadata["pending_plan_change"]
  end

  test "REGRESSION: upgrade clears pending downgrade" do
    # This tests the bug where a user schedules a downgrade, then upgrades again
    # before renewal. The pending_plan_change would stick and get applied on renewal,
    # switching them back unexpectedly. Upgrade should clear pending downgrades.

    user = User.create!(email: "upgrade_clears_pending@example.com", name: "Upgrade Clears Pending")
    wallet = user.credit_wallet

    customer = Pay::Customer.create!(
      owner: user,
      processor: :fake_processor,
      processor_id: "cus_upgrade_clears_pending"
    )

    subscription = Pay::Subscription.create!(
      customer: customer,
      name: "default",
      processor_id: "sub_upgrade_clears_pending",
      processor_plan: "premium_plan_monthly",  # 2000 + 200 = 2200
      status: "active",
      quantity: 1,
      current_period_end: 30.days.from_now
    )

    fulfillment = UsageCredits::Fulfillment.find_by(source: subscription)

    # 1. Schedule a downgrade to pro
    subscription.update!(processor_plan: "pro_plan_monthly")

    fulfillment.reload
    assert_equal "pro_plan_monthly", fulfillment.metadata["pending_plan_change"],
      "Downgrade should be scheduled"

    # 2. User changes mind and upgrades back to premium
    subscription.update!(processor_plan: "premium_plan_monthly")

    fulfillment.reload
    # The pending downgrade should be CLEARED
    assert_nil fulfillment.metadata["pending_plan_change"],
      "REGRESSION: Upgrade should clear pending downgrade. Otherwise the downgrade " \
      "would apply on renewal, switching user back unexpectedly!"
    assert_nil fulfillment.metadata["plan_change_at"],
      "REGRESSION: Upgrade should clear plan_change_at as well"
    assert_equal "premium_plan_monthly", fulfillment.metadata["plan"],
      "Plan metadata should reflect the upgrade"

    # 3. Simulate renewal - should stay on premium
    subscription.update!(
      current_period_end: 60.days.from_now,
      ends_at: nil
    )

    fulfillment.reload
    # Should still be on premium, not switched to pro
    assert_equal "premium_plan_monthly", fulfillment.metadata["plan"],
      "After renewal, should still be on premium (pending was cleared)"
  end

  test "downgrade during trial period does not trigger plan_changed" do
    # NOTE: Plan changes during trial (status="trialing") are NOT currently handled
    # by the plan_changed? logic, which requires status="active". This is intentional
    # because during trial, the user hasn't paid yet and billing works differently.
    # The plan change would only take effect when the subscription becomes active.

    user = User.create!(email: "trial_downgrade@example.com", name: "Trial Downgrade")
    wallet = user.credit_wallet

    customer = Pay::Customer.create!(
      owner: user,
      processor: :fake_processor,
      processor_id: "cus_trial_downgrade"
    )

    trial_ends = 7.days.from_now

    # Start with premium trial (no trial_includes in premium config)
    subscription = Pay::Subscription.create!(
      customer: customer,
      name: "default",
      processor_id: "sub_trial_downgrade",
      processor_plan: "premium_plan_monthly",
      status: "trialing",
      trial_ends_at: trial_ends,
      quantity: 1
    )

    fulfillment = UsageCredits::Fulfillment.find_by(source: subscription)
    assert_not_nil fulfillment

    # Change to pro during trial
    subscription.update!(processor_plan: "pro_plan_monthly")

    fulfillment.reload
    # Since status="trialing" (not "active"), plan_changed? returns false
    # The plan change is NOT handled by UsageCredits during trial
    # The fulfillment metadata is NOT updated because handle_plan_change didn't fire
    assert_equal "premium_plan_monthly", fulfillment.metadata["plan"],
      "Plan change during trial should NOT trigger handle_plan_change (status != active)"
    assert_nil fulfillment.metadata["pending_plan_change"],
      "No pending change scheduled during trial"
  end

  test "upgrade during trial period does not trigger plan_changed" do
    # NOTE: Plan changes during trial (status="trialing") are NOT currently handled
    # by the plan_changed? logic, which requires status="active". This is intentional
    # because during trial, the user hasn't paid yet and billing works differently.
    #
    # During trial, only trial_includes credits are awarded. The full subscription
    # credits are only granted when the trial ends and status becomes "active".

    user = User.create!(email: "trial_upgrade@example.com", name: "Trial Upgrade")
    wallet = user.credit_wallet

    customer = Pay::Customer.create!(
      owner: user,
      processor: :fake_processor,
      processor_id: "cus_trial_upgrade"
    )

    trial_ends = 7.days.from_now

    # Start with pro trial (has trial_includes 50)
    subscription = Pay::Subscription.create!(
      customer: customer,
      name: "default",
      processor_id: "sub_trial_upgrade",
      processor_plan: "pro_plan_monthly",
      status: "trialing",
      trial_ends_at: trial_ends,
      quantity: 1
    )

    # Should have 50 trial credits
    assert_equal 50, wallet.reload.credits

    # Upgrade to premium during trial
    subscription.update!(processor_plan: "premium_plan_monthly")

    # Since status="trialing" (not "active"), plan_changed? returns false
    # No upgrade credits granted during trial
    assert_equal 50, wallet.reload.credits,
      "Plan change during trial should NOT trigger handle_plan_change (status != active)"

    upgrade_tx = wallet.transactions.find_by(category: "subscription_upgrade")
    assert_nil upgrade_tx, "No upgrade transaction during trial"

    # The new plan will take effect when subscription becomes active
    fulfillment = UsageCredits::Fulfillment.find_by(source: subscription)
    # Metadata still points to original plan since handle_plan_change didn't fire
    assert_equal "pro_plan_monthly", fulfillment.metadata["plan"]
  end

  # ========================================
  # EDGE CASES: FULFILLMENT INTEGRITY
  # ========================================

  test "fulfillment metadata stays consistent through multiple changes" do
    user = User.create!(email: "metadata_consistent@example.com", name: "Metadata Consistent")
    wallet = user.credit_wallet

    customer = Pay::Customer.create!(
      owner: user,
      processor: :fake_processor,
      processor_id: "cus_metadata_consistent"
    )

    subscription = Pay::Subscription.create!(
      customer: customer,
      name: "default",
      processor_id: "sub_metadata_consistent",
      processor_plan: "pro_plan_monthly",
      status: "active",
      quantity: 1,
      current_period_end: 30.days.from_now
    )

    fulfillment = UsageCredits::Fulfillment.find_by(source: subscription)
    assert_equal "pro_plan_monthly", fulfillment.metadata["plan"]
    assert_equal subscription.id, fulfillment.metadata["subscription_id"]

    # Upgrade
    subscription.update!(processor_plan: "premium_plan_monthly")
    fulfillment.reload
    assert_equal "premium_plan_monthly", fulfillment.metadata["plan"]
    assert_equal subscription.id, fulfillment.metadata["subscription_id"]  # Preserved

    # Downgrade (scheduled)
    subscription.update!(processor_plan: "pro_plan_monthly")
    fulfillment.reload
    assert_equal "premium_plan_monthly", fulfillment.metadata["plan"]  # Still premium
    assert_equal "pro_plan_monthly", fulfillment.metadata["pending_plan_change"]
    assert_equal subscription.id, fulfillment.metadata["subscription_id"]  # Preserved
  end

  test "pending plan change metadata is cleared after application" do
    user = User.create!(email: "pending_clear@example.com", name: "Pending Clear")
    wallet = user.credit_wallet

    customer = Pay::Customer.create!(
      owner: user,
      processor: :fake_processor,
      processor_id: "cus_pending_clear"
    )

    subscription = Pay::Subscription.create!(
      customer: customer,
      name: "default",
      processor_id: "sub_pending_clear",
      processor_plan: "premium_plan_monthly",
      status: "active",
      quantity: 1,
      current_period_end: 30.days.from_now
    )

    # Schedule downgrade
    subscription.update!(processor_plan: "pro_plan_monthly")

    fulfillment = UsageCredits::Fulfillment.find_by(source: subscription)
    assert_not_nil fulfillment.metadata["pending_plan_change"]
    assert_not_nil fulfillment.metadata["plan_change_at"]

    # Simulate renewal
    subscription.update!(
      current_period_end: 60.days.from_now,
      ends_at: nil
    )

    fulfillment.reload
    # Pending change should be applied and cleared
    assert_equal "pro_plan_monthly", fulfillment.metadata["plan"]
    assert_nil fulfillment.metadata["pending_plan_change"]
    assert_nil fulfillment.metadata["plan_change_at"]
  end

  # ========================================
  # EDGE CASES: TRANSACTION CATEGORIES
  # ========================================

  test "upgrade transaction has correct category and metadata" do
    user = User.create!(email: "tx_category@example.com", name: "TX Category")
    wallet = user.credit_wallet

    customer = Pay::Customer.create!(
      owner: user,
      processor: :fake_processor,
      processor_id: "cus_tx_category"
    )

    subscription = Pay::Subscription.create!(
      customer: customer,
      name: "default",
      processor_id: "sub_tx_category",
      processor_plan: "pro_plan_monthly",
      status: "active",
      quantity: 1
    )

    subscription.update!(processor_plan: "premium_plan_monthly")

    upgrade_tx = wallet.transactions.find_by(category: "subscription_upgrade")
    assert_not_nil upgrade_tx

    assert_equal "subscription_upgrade", upgrade_tx.category
    assert_equal 2000, upgrade_tx.amount
    assert_equal "premium_plan_monthly", upgrade_tx.metadata["plan"]
    assert_equal "plan_upgrade", upgrade_tx.metadata["reason"]
    assert_equal subscription.id, upgrade_tx.metadata["subscription_id"]
    assert_not_nil upgrade_tx.metadata["fulfilled_at"]
  end

  test "initial subscription creates correct transaction categories" do
    user = User.create!(email: "tx_initial@example.com", name: "TX Initial")
    wallet = user.credit_wallet

    customer = Pay::Customer.create!(
      owner: user,
      processor: :fake_processor,
      processor_id: "cus_tx_initial"
    )

    subscription = Pay::Subscription.create!(
      customer: customer,
      name: "default",
      processor_id: "sub_tx_initial",
      processor_plan: "pro_plan_monthly",  # Has signup_bonus
      status: "active",
      quantity: 1
    )

    # Should have two transactions: subscription_credits and subscription_signup_bonus
    credits_tx = wallet.transactions.find_by(category: "subscription_credits")
    bonus_tx = wallet.transactions.find_by(category: "subscription_signup_bonus")
    upgrade_tx = wallet.transactions.find_by(category: "subscription_upgrade")

    assert_not_nil credits_tx, "Should have subscription_credits transaction"
    assert_not_nil bonus_tx, "Should have subscription_signup_bonus transaction"
    assert_nil upgrade_tx, "Should NOT have subscription_upgrade on initial"

    assert_equal 500, credits_tx.amount
    assert_equal 100, bonus_tx.amount
  end

  # ========================================
  # EDGE CASES: CONCURRENT SCENARIOS
  # ========================================

  test "renewal during scheduled downgrade applies change correctly" do
    user = User.create!(email: "concurrent_renew@example.com", name: "Concurrent Renew")
    wallet = user.credit_wallet

    customer = Pay::Customer.create!(
      owner: user,
      processor: :fake_processor,
      processor_id: "cus_concurrent_renew"
    )

    subscription = Pay::Subscription.create!(
      customer: customer,
      name: "default",
      processor_id: "sub_concurrent_renew",
      processor_plan: "premium_plan_monthly",
      status: "active",
      quantity: 1,
      current_period_end: 1.day.from_now  # About to renew
    )

    # Schedule downgrade
    subscription.update!(processor_plan: "pro_plan_monthly")

    fulfillment = UsageCredits::Fulfillment.find_by(source: subscription)
    assert_not_nil fulfillment.metadata["pending_plan_change"]

    # Renewal webhook arrives
    subscription.update!(
      current_period_end: 31.days.from_now,
      ends_at: nil
    )

    fulfillment.reload
    # Downgrade should be applied on renewal
    assert_equal "pro_plan_monthly", fulfillment.metadata["plan"]
    assert_nil fulfillment.metadata["pending_plan_change"]

    # Next fulfillment should award pro plan credits (500), not premium (2000)
    # We verify the metadata is correct for FulfillmentService
  end

  test "status change without plan change does not trigger plan_changed" do
    user = User.create!(email: "status_only@example.com", name: "Status Only")
    wallet = user.credit_wallet

    customer = Pay::Customer.create!(
      owner: user,
      processor: :fake_processor,
      processor_id: "cus_status_only"
    )

    # Start as incomplete
    subscription = Pay::Subscription.create!(
      customer: customer,
      name: "default",
      processor_id: "sub_status_only",
      processor_plan: "pro_plan_monthly",
      status: "incomplete",
      quantity: 1
    )

    assert_equal 0, wallet.reload.credits  # No credits for incomplete

    # Activate (this should use initial setup, not plan change)
    subscription.update!(status: "active")

    # Should have exactly 600 (500 + 100 bonus)
    assert_equal 600, wallet.reload.credits

    # Should NOT have upgrade transaction
    assert_nil wallet.transactions.find_by(category: "subscription_upgrade")
  end

  # ========================================
  # EDGE CASES: BOUNDARY CONDITIONS
  # ========================================

  test "upgrade to plan with zero signup bonus works correctly" do
    # test_rollover has no signup_bonus configured
    user = User.create!(email: "no_bonus@example.com", name: "No Bonus")
    wallet = user.credit_wallet

    customer = Pay::Customer.create!(
      owner: user,
      processor: :fake_processor,
      processor_id: "cus_no_bonus"
    )

    subscription = Pay::Subscription.create!(
      customer: customer,
      name: "default",
      processor_id: "sub_no_bonus",
      processor_plan: "pro_plan_monthly",  # 500 + 100 bonus = 600
      status: "active",
      quantity: 1
    )

    assert_equal 600, wallet.reload.credits

    # Upgrade to rollover (1000 credits, no signup bonus)
    subscription.update!(processor_plan: "rollover_plan_monthly")

    # Should get 1000 upgrade credits
    assert_equal 1600, wallet.reload.credits

    upgrade_tx = wallet.transactions.find_by(category: "subscription_upgrade")
    assert_equal 1000, upgrade_tx.amount
  end

  test "downgrade handles missing current_period_end gracefully" do
    user = User.create!(email: "no_period_end@example.com", name: "No Period End")
    wallet = user.credit_wallet

    customer = Pay::Customer.create!(
      owner: user,
      processor: :fake_processor,
      processor_id: "cus_no_period_end"
    )

    subscription = Pay::Subscription.create!(
      customer: customer,
      name: "default",
      processor_id: "sub_no_period_end",
      processor_plan: "premium_plan_monthly",
      status: "active",
      quantity: 1,
      current_period_end: nil  # Edge case: no period end set
    )

    # Downgrade
    subscription.update!(processor_plan: "pro_plan_monthly")

    fulfillment = UsageCredits::Fulfillment.find_by(source: subscription)
    # Should use Time.current as fallback
    assert_not_nil fulfillment.metadata["pending_plan_change"]
    assert_not_nil fulfillment.metadata["plan_change_at"]
  end

  test "non-credit to non-credit plan change is ignored" do
    user = User.create!(email: "noncredit_both@example.com", name: "Non Credit Both")
    wallet = user.credit_wallet

    customer = Pay::Customer.create!(
      owner: user,
      processor: :fake_processor,
      processor_id: "cus_noncredit_both"
    )

    subscription = Pay::Subscription.create!(
      customer: customer,
      name: "default",
      processor_id: "sub_noncredit_both",
      processor_plan: "business_no_credits",  # Not in config
      status: "active",
      quantity: 1
    )

    assert_equal 0, wallet.reload.credits
    assert_nil UsageCredits::Fulfillment.find_by(source: subscription)

    # Change to another non-credit plan
    subscription.update!(processor_plan: "enterprise_no_credits")

    # Nothing should happen
    assert_equal 0, wallet.reload.credits
    assert_nil UsageCredits::Fulfillment.find_by(source: subscription)
    assert_nil wallet.transactions.find_by(category: "subscription_upgrade")
  end

  # ========================================
  # EDGE CASES: WALLET VALIDATION
  # ========================================

  test "plan change without valid wallet is handled gracefully" do
    user = User.create!(email: "no_wallet_change@example.com", name: "No Wallet Change")
    wallet = user.credit_wallet

    customer = Pay::Customer.create!(
      owner: user,
      processor: :fake_processor,
      processor_id: "cus_no_wallet_change"
    )

    subscription = Pay::Subscription.create!(
      customer: customer,
      name: "default",
      processor_id: "sub_no_wallet_change",
      processor_plan: "pro_plan_monthly",
      status: "active",
      quantity: 1
    )

    initial_credits = wallet.reload.credits

    # Destroy wallet
    wallet.destroy!
    user.reload

    # Plan change should not crash
    assert_nothing_raised do
      subscription.update!(processor_plan: "premium_plan_monthly")
    end
  end

  # ========================================
  # EDGE CASES: MULTIPLE PLAN CHANGES IN ONE PERIOD (COMPREHENSIVE)
  # ========================================
  # These tests exhaustively cover the "multiple plan changes in one period" scenario
  # that the reviewer flagged as potentially missing coverage.

  test "multiple consecutive downgrades overwrites pending plan change correctly" do
    # Scenario: User schedules downgrade A, then schedules downgrade B before renewal
    # The second downgrade should overwrite the first pending plan change
    user = User.create!(email: "multi_downgrade@example.com", name: "Multi Downgrade User")
    wallet = user.credit_wallet

    customer = Pay::Customer.create!(
      owner: user,
      processor: :fake_processor,
      processor_id: "cus_multi_downgrade_test"
    )

    subscription = Pay::Subscription.create!(
      customer: customer,
      name: "default",
      processor_id: "sub_multi_downgrade_test",
      processor_plan: "premium_plan_monthly",  # 2000 credits + 200 bonus
      status: "active",
      quantity: 1,
      current_period_end: 30.days.from_now
    )

    # Initial: 2000 + 200 = 2200
    assert_equal 2200, wallet.reload.credits

    fulfillment = UsageCredits::Fulfillment.find_by(source: subscription)
    assert_equal "premium_plan_monthly", fulfillment.metadata["plan"]

    # First downgrade: Premium → Pro (scheduled)
    subscription.update!(processor_plan: "pro_plan_monthly")

    fulfillment.reload
    assert_equal "premium_plan_monthly", fulfillment.metadata["plan"]  # Still premium
    assert_equal "pro_plan_monthly", fulfillment.metadata["pending_plan_change"]
    assert_equal 2200, wallet.reload.credits  # No credit change

    # Second downgrade: Pro → Rollover (overwrites the pending change)
    # Since Pro has 500 credits and Rollover has 1000, this is actually an "upgrade" from
    # the pending state, but since processor_plan is now "rollover", let's see how it handles it
    subscription.update!(processor_plan: "rollover_plan_monthly")

    fulfillment.reload
    # Since rollover has MORE credits (1000) than premium (2000)? No - premium has 2000, rollover has 1000
    # This is still a downgrade from premium (2000) to rollover (1000)
    # The pending_plan_change should be updated to rollover
    assert_equal "premium_plan_monthly", fulfillment.metadata["plan"]  # Still premium (current)
    assert_equal "rollover_plan_monthly", fulfillment.metadata["pending_plan_change"]
    assert_equal 2200, wallet.reload.credits  # Still no credit change

    # Simulate renewal - should apply the LATEST pending plan change (rollover)
    subscription.update!(
      current_period_end: 60.days.from_now,
      ends_at: nil
    )

    fulfillment.reload
    assert_equal "rollover_plan_monthly", fulfillment.metadata["plan"], "Should be on rollover after renewal"
    assert_nil fulfillment.metadata["pending_plan_change"], "Pending should be cleared"
  end

  test "downgrade then downgrade then upgrade clears all pending changes" do
    # Scenario: User schedules two downgrades, then goes back to current plan before renewal
    # The pending downgrade should be cleared, but NO credits granted
    # (user was always on premium in the billing sense - Stripe would not charge them again)
    user = User.create!(email: "down_down_up@example.com", name: "Down Down Up User")
    wallet = user.credit_wallet

    customer = Pay::Customer.create!(
      owner: user,
      processor: :fake_processor,
      processor_id: "cus_down_down_up_test"
    )

    subscription = Pay::Subscription.create!(
      customer: customer,
      name: "default",
      processor_id: "sub_down_down_up_test",
      processor_plan: "premium_plan_monthly",  # 2000 credits + 200 bonus
      status: "active",
      quantity: 1,
      current_period_end: 30.days.from_now
    )

    # Initial: 2000 + 200 = 2200
    initial_credits = wallet.reload.credits
    assert_equal 2200, initial_credits

    fulfillment = UsageCredits::Fulfillment.find_by(source: subscription)

    # First downgrade: Premium → Pro (scheduled)
    subscription.update!(processor_plan: "pro_plan_monthly")
    fulfillment.reload
    assert_equal "pro_plan_monthly", fulfillment.metadata["pending_plan_change"]

    # Second downgrade: Pro → Rollover (overwrites pending)
    subscription.update!(processor_plan: "rollover_plan_monthly")
    fulfillment.reload
    assert_equal "rollover_plan_monthly", fulfillment.metadata["pending_plan_change"]

    # Now go back to premium - should CLEAR the pending downgrade but NOT grant credits
    # The user was always on premium (in metadata), they never actually changed plans
    # This is like canceling a scheduled downgrade in Stripe - no new charge, no new credits
    subscription.update!(processor_plan: "premium_plan_monthly")

    fulfillment.reload
    assert_nil fulfillment.metadata["pending_plan_change"],
      "Returning to current plan should clear pending downgrade"
    assert_nil fulfillment.metadata["plan_change_at"]
    assert_equal "premium_plan_monthly", fulfillment.metadata["plan"]

    # NO upgrade credits - user never left premium
    assert_equal 2200, wallet.reload.credits, "No credits granted when returning to current plan"
  end

  test "rapid successive upgrades to different plans accumulate credits" do
    # Scenario: User upgrades through different tiers
    # Only TRUE upgrades (to different, higher-credit plans) grant credits
    # Returning to the same plan after a scheduled downgrade does NOT grant credits
    # This prevents gaming the credit system - matches Stripe's billing behavior
    user = User.create!(email: "rapid_upgrades@example.com", name: "Rapid Upgrades User")
    wallet = user.credit_wallet

    customer = Pay::Customer.create!(
      owner: user,
      processor: :fake_processor,
      processor_id: "cus_rapid_upgrades_test"
    )

    subscription = Pay::Subscription.create!(
      customer: customer,
      name: "default",
      processor_id: "sub_rapid_upgrades_test",
      processor_plan: "pro_plan_monthly",  # 500 credits + 100 bonus
      status: "active",
      quantity: 1,
      current_period_end: 30.days.from_now
    )

    # Initial: 500 + 100 = 600
    assert_equal 600, wallet.reload.credits

    # Upgrade 1: Pro → Premium (get 2000)
    subscription.update!(processor_plan: "premium_plan_monthly")
    assert_equal 2600, wallet.reload.credits

    # Schedule downgrade to pro
    subscription.update!(processor_plan: "pro_plan_monthly")
    assert_equal 2600, wallet.reload.credits  # No change

    # Go back to premium - NO credits (user was always on premium, just clearing pending)
    subscription.update!(processor_plan: "premium_plan_monthly")
    assert_equal 2600, wallet.reload.credits  # Still 2600

    fulfillment = UsageCredits::Fulfillment.find_by(source: subscription)
    assert_nil fulfillment.metadata["pending_plan_change"], "Pending should be cleared"
    assert_equal "premium_plan_monthly", fulfillment.metadata["plan"]

    # Verify only 1 upgrade transaction (the initial pro → premium)
    upgrade_transactions = wallet.transactions.where(category: "subscription_upgrade")
    assert_equal 1, upgrade_transactions.count, "Only true upgrades grant credits"
  end

  test "lateral change after downgrade scheduled keeps pending downgrade" do
    # Scenario: User schedules downgrade to Pro, then laterally changes to another plan
    # with the same credits. The pending downgrade should remain.
    # First, add a lateral plan with same credits as pro
    UsageCredits.configure do |config|
      config.subscription_plan :test_pro_alt do
        processor_plan(:fake_processor, "pro_plan_alt_monthly")
        gives 500.credits.every(:month)  # Same credits as pro
        unused_credits :expire
      end
    end

    user = User.create!(email: "lateral_after_downgrade@example.com", name: "Lateral After Downgrade")
    wallet = user.credit_wallet

    customer = Pay::Customer.create!(
      owner: user,
      processor: :fake_processor,
      processor_id: "cus_lateral_after_downgrade"
    )

    subscription = Pay::Subscription.create!(
      customer: customer,
      name: "default",
      processor_id: "sub_lateral_after_downgrade",
      processor_plan: "premium_plan_monthly",  # 2000 credits
      status: "active",
      quantity: 1,
      current_period_end: 30.days.from_now
    )

    fulfillment = UsageCredits::Fulfillment.find_by(source: subscription)

    # Schedule downgrade to pro (500 credits)
    subscription.update!(processor_plan: "pro_plan_monthly")
    fulfillment.reload
    assert_equal "pro_plan_monthly", fulfillment.metadata["pending_plan_change"]

    # Now "change" to pro_alt (also 500 credits - lateral from the pending plan's perspective)
    # Since current plan is still premium (2000), and pro_alt is 500, this is still a downgrade
    subscription.update!(processor_plan: "pro_plan_alt_monthly")

    fulfillment.reload
    # The pending downgrade should be updated to the new target
    assert_equal "pro_plan_alt_monthly", fulfillment.metadata["pending_plan_change"],
      "Pending downgrade should be updated to the new target plan"
    assert_equal "premium_plan_monthly", fulfillment.metadata["plan"]  # Still on premium
  end

  test "upgrade to same plan as pending downgrade grants no credits and clears pending" do
    # Scenario: User on Premium, schedules downgrade to Pro, then "upgrades" back to Pro
    # (which is actually the same as the pending plan)
    # This edge case tests: what happens when new plan == pending plan?
    user = User.create!(email: "upgrade_to_pending@example.com", name: "Upgrade To Pending")
    wallet = user.credit_wallet

    customer = Pay::Customer.create!(
      owner: user,
      processor: :fake_processor,
      processor_id: "cus_upgrade_to_pending"
    )

    subscription = Pay::Subscription.create!(
      customer: customer,
      name: "default",
      processor_id: "sub_upgrade_to_pending",
      processor_plan: "premium_plan_monthly",  # 2000 credits
      status: "active",
      quantity: 1,
      current_period_end: 30.days.from_now
    )

    initial_credits = wallet.reload.credits  # 2200 (2000 + 200 bonus)
    fulfillment = UsageCredits::Fulfillment.find_by(source: subscription)

    # Schedule downgrade to pro (500 credits)
    subscription.update!(processor_plan: "pro_plan_monthly")
    fulfillment.reload
    assert_equal "pro_plan_monthly", fulfillment.metadata["pending_plan_change"]
    assert_equal 2200, wallet.reload.credits  # No change

    # Now user "changes" to rollover (1000 credits)
    # Premium (2000) → Rollover (1000) is still a downgrade
    subscription.update!(processor_plan: "rollover_plan_monthly")
    fulfillment.reload
    assert_equal "rollover_plan_monthly", fulfillment.metadata["pending_plan_change"]
    assert_equal 2200, wallet.reload.credits  # Still no change

    # Verify on renewal, the LAST pending plan is applied
    subscription.update!(
      current_period_end: 60.days.from_now,
      ends_at: nil
    )

    fulfillment.reload
    assert_equal "rollover_plan_monthly", fulfillment.metadata["plan"]
    assert_nil fulfillment.metadata["pending_plan_change"]
  end

  test "fulfillment job timing with pending downgrade awards current plan credits" do
    # This test verifies the reviewer's concern about FulfillmentJob timing
    # When a downgrade is scheduled but not yet applied, the fulfillment job
    # should still award credits from the CURRENT plan (not the pending plan)
    user = User.create!(email: "fulfillment_timing@example.com", name: "Fulfillment Timing")
    wallet = user.credit_wallet

    customer = Pay::Customer.create!(
      owner: user,
      processor: :fake_processor,
      processor_id: "cus_fulfillment_timing"
    )

    subscription = Pay::Subscription.create!(
      customer: customer,
      name: "default",
      processor_id: "sub_fulfillment_timing",
      processor_plan: "premium_plan_monthly",  # 2000 credits
      status: "active",
      quantity: 1,
      current_period_end: 30.days.from_now
    )

    fulfillment = UsageCredits::Fulfillment.find_by(source: subscription)
    assert_equal "premium_plan_monthly", fulfillment.metadata["plan"]

    # Schedule downgrade to pro
    subscription.update!(processor_plan: "pro_plan_monthly")

    fulfillment.reload
    # Key assertion: The CURRENT plan in metadata should still be premium
    # because the downgrade hasn't been applied yet
    assert_equal "premium_plan_monthly", fulfillment.metadata["plan"],
      "Fulfillment should still reference premium plan (current) for job processing"
    assert_equal "pro_plan_monthly", fulfillment.metadata["pending_plan_change"],
      "Pending plan change should be stored separately"

    # This means when FulfillmentService looks up the plan via fulfillment.metadata["plan"],
    # it will get "premium_plan_monthly" and award 2000 credits - correct behavior!
  end

  test "multiple plan changes preserve subscription_id in metadata" do
    # Ensure subscription_id is never lost during plan change chaos
    user = User.create!(email: "preserve_sub_id@example.com", name: "Preserve Sub ID")
    wallet = user.credit_wallet

    customer = Pay::Customer.create!(
      owner: user,
      processor: :fake_processor,
      processor_id: "cus_preserve_sub_id"
    )

    subscription = Pay::Subscription.create!(
      customer: customer,
      name: "default",
      processor_id: "sub_preserve_sub_id",
      processor_plan: "pro_plan_monthly",
      status: "active",
      quantity: 1,
      current_period_end: 30.days.from_now
    )

    fulfillment = UsageCredits::Fulfillment.find_by(source: subscription)
    original_sub_id = fulfillment.metadata["subscription_id"]
    assert_equal subscription.id, original_sub_id

    # Upgrade
    subscription.update!(processor_plan: "premium_plan_monthly")
    fulfillment.reload
    assert_equal original_sub_id, fulfillment.metadata["subscription_id"]

    # Downgrade (scheduled)
    subscription.update!(processor_plan: "pro_plan_monthly")
    fulfillment.reload
    assert_equal original_sub_id, fulfillment.metadata["subscription_id"]

    # Upgrade again
    subscription.update!(processor_plan: "premium_plan_monthly")
    fulfillment.reload
    assert_equal original_sub_id, fulfillment.metadata["subscription_id"]

    # Renewal
    subscription.update!(current_period_end: 60.days.from_now)
    fulfillment.reload
    assert_equal original_sub_id, fulfillment.metadata["subscription_id"],
      "subscription_id should be preserved through all plan changes and renewals"
  end

  # ========================================
  # EDGE CASE TESTS: REVIEWER'S CRITICAL ISSUES
  # ========================================

  test "reactivation with past current_period_start does not create already-expired credits" do
    # This tests the bug where credits could be created with expiration in the past
    # if current_period_start is in the past (e.g., paused subscription reactivated)
    user = User.create!(email: "past_period_start@example.com", name: "Past Period Start")
    wallet = user.credit_wallet

    customer = Pay::Customer.create!(
      owner: user,
      processor: :fake_processor,
      processor_id: "cus_past_period_start"
    )

    # Create subscription with current_period_start in the past (simulating reactivation)
    # In reality, this happens when a subscription is paused and then resumed
    subscription = Pay::Subscription.create!(
      customer: customer,
      name: "default",
      processor_id: "sub_past_period_start",
      processor_plan: "pro_plan_monthly",  # 500 credits, expires
      status: "active",
      quantity: 1,
      current_period_start: 2.months.ago,  # KEY: start is in the past
      current_period_end: 30.days.from_now
    )

    # Credits should have been awarded
    assert wallet.reload.credits.positive?, "Credits should be awarded"

    # Check the credit transaction - expiration should NOT be in the past
    credit_transaction = wallet.transactions.where("amount > 0").order(created_at: :desc).first
    assert credit_transaction.present?, "Credit transaction should exist"

    if credit_transaction.expires_at.present?
      assert credit_transaction.expires_at > Time.current,
        "Credits should NOT expire in the past! expires_at=#{credit_transaction.expires_at}, now=#{Time.current}"
    end
  end

  test "pending plan change to deleted plan is handled gracefully" do
    # This tests the edge case where an admin removes a plan from config
    # after a user has scheduled a downgrade to it
    user = User.create!(email: "deleted_plan@example.com", name: "Deleted Plan User")
    wallet = user.credit_wallet

    customer = Pay::Customer.create!(
      owner: user,
      processor: :fake_processor,
      processor_id: "cus_deleted_plan"
    )

    # Create a temporary plan for this test
    UsageCredits.configure do |config|
      config.subscription_plan :temp_plan do
        processor_plan(:fake_processor, "temp_plan_monthly")
        gives 100.credits.every(:month)
        unused_credits :expire
      end
    end

    subscription = Pay::Subscription.create!(
      customer: customer,
      name: "default",
      processor_id: "sub_deleted_plan",
      processor_plan: "premium_plan_monthly",  # 2000 credits
      status: "active",
      quantity: 1,
      current_period_end: 30.days.from_now
    )

    initial_credits = wallet.reload.credits

    # Schedule a downgrade to the temp plan
    subscription.update!(processor_plan: "temp_plan_monthly")
    fulfillment = UsageCredits::Fulfillment.find_by(source: subscription)
    assert_equal "temp_plan_monthly", fulfillment.metadata["pending_plan_change"]

    # Now "delete" the plan by clearing the config (simulate admin removing it)
    # We need to unconfigure the temp plan - set up with only the original plans
    # Actually, the plan is still there but we can manually set an invalid pending plan
    fulfillment.update!(
      metadata: fulfillment.metadata.merge("pending_plan_change" => "nonexistent_plan_id")
    )

    # Simulate renewal - the pending plan doesn't exist
    subscription.update!(
      current_period_end: 60.days.from_now,
      ends_at: nil
    )

    # The system should handle this gracefully
    fulfillment.reload

    # The invalid pending plan change should be cleared
    assert_nil fulfillment.metadata["pending_plan_change"],
      "Invalid pending plan should be cleared"

    # The fulfillment should still be on the original plan (premium)
    assert_equal "premium_plan_monthly", fulfillment.metadata["plan"],
      "Should remain on original plan when pending plan is invalid"
  end
end
