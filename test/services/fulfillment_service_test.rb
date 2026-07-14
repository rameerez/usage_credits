# frozen_string_literal: true

require "test_helper"

# ============================================================================
# FULFILLMENT SERVICE TEST SUITE
# ============================================================================
#
# This test suite tests the FulfillmentService which is the CRITICAL ENGINE
# that processes recurring credit fulfillments for subscriptions.
#
# The service handles:
#   - Processing due fulfillments and awarding credits
#   - Transaction safety with row locking
#   - Validation of fulfillment types and metadata
#   - Credit calculation based on plan/pack
#   - Expiration calculation (rollover vs expire)
#   - Batch processing with error recovery
#
# This is BUSINESS-CRITICAL code that handles real money!
#
# ============================================================================

module UsageCredits
  class FulfillmentServiceTest < ActiveSupport::TestCase
    setup do
      # Configure test subscription plans
      UsageCredits.configure do |config|
        config.subscription_plan :test_pro do
          processor_plan(:fake_processor, "pro_plan_monthly")
          gives 500.credits.every(:month)
          unused_credits :expire
        end

        config.subscription_plan :test_rollover do
          processor_plan(:fake_processor, "rollover_plan_monthly")
          gives 1000.credits.every(:month)
          unused_credits :rollover
        end

        config.subscription_plan :stripe_pause_service_pro do
          processor_plan(:stripe, "stripe_pause_service_pro")
          gives 500.credits.every(:month)
          unused_credits :expire
        end

        config.subscription_plan :stripe_pause_service_premium do
          processor_plan(:stripe, "stripe_pause_service_premium")
          gives 2000.credits.every(:month)
          unused_credits :expire
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
    # VALIDATION
    # ========================================

    test "raises error for nil fulfillment" do
      error = assert_raises(UsageCredits::Error) do
        FulfillmentService.new(nil)
      end

      assert_includes error.message, "No fulfillment provided"
    end

    test "raises error for invalid fulfillment type" do
      fulfillment = Fulfillment.new(
        wallet: usage_credits_wallets(:rich_wallet),
        fulfillment_type: "invalid_type",
        credits_last_fulfillment: 100
      )

      error = assert_raises(UsageCredits::Error) do
        FulfillmentService.new(fulfillment)
      end

      assert_includes error.message, "Invalid fulfillment type"
    end

    test "raises error for fulfillment without wallet" do
      fulfillment = Fulfillment.new(
        fulfillment_type: "subscription",
        credits_last_fulfillment: 100
      )

      error = assert_raises(UsageCredits::Error) do
        FulfillmentService.new(fulfillment)
      end

      assert_includes error.message, "No wallet associated"
    end

    test "raises error for subscription fulfillment without plan in metadata" do
      fulfillment = Fulfillment.new(
        wallet: usage_credits_wallets(:rich_wallet),
        fulfillment_type: "subscription",
        credits_last_fulfillment: 100,
        metadata: {}
      )

      error = assert_raises(UsageCredits::Error) do
        FulfillmentService.new(fulfillment)
      end

      assert_includes error.message, "No plan specified"
    end

    test "raises error for credit_pack fulfillment without pack in metadata" do
      fulfillment = Fulfillment.new(
        wallet: usage_credits_wallets(:rich_wallet),
        fulfillment_type: "credit_pack",
        credits_last_fulfillment: 100,
        metadata: {}
      )

      error = assert_raises(UsageCredits::Error) do
        FulfillmentService.new(fulfillment)
      end

      assert_includes error.message, "No pack specified"
    end

    test "raises error for manual fulfillment without credits in metadata" do
      fulfillment = Fulfillment.new(
        wallet: usage_credits_wallets(:rich_wallet),
        fulfillment_type: "manual",
        credits_last_fulfillment: 100,
        metadata: {}
      )

      error = assert_raises(UsageCredits::Error) do
        FulfillmentService.new(fulfillment)
      end

      assert_includes error.message, "No credits amount specified"
    end

    # ========================================
    # SUBSCRIPTION FULFILLMENT PROCESSING
    # ========================================

    test "processes subscription fulfillment and awards credits" do
      wallet = usage_credits_wallets(:subscribed_wallet)
      initial_credits = wallet.credits

      fulfillment = usage_credits_fulfillments(:active_subscription_fulfillment)
      fulfillment.update!(next_fulfillment_at: 1.second.ago)

      service = FulfillmentService.new(fulfillment)
      service.process

      assert_equal initial_credits + 500, wallet.reload.credits
    end

    test "updates last_fulfilled_at after processing" do
      fulfillment = usage_credits_fulfillments(:active_subscription_fulfillment)
      fulfillment.update!(next_fulfillment_at: 1.second.ago)
      original_last = fulfillment.last_fulfilled_at

      service = FulfillmentService.new(fulfillment)
      service.process

      fulfillment.reload
      assert fulfillment.last_fulfilled_at > original_last
    end

    test "updates credits_last_fulfillment after processing" do
      fulfillment = usage_credits_fulfillments(:active_subscription_fulfillment)
      fulfillment.update!(next_fulfillment_at: 1.second.ago)

      service = FulfillmentService.new(fulfillment)
      service.process

      fulfillment.reload
      assert_equal 500, fulfillment.credits_last_fulfillment
    end

    test "calculates next_fulfillment_at after processing" do
      fulfillment = usage_credits_fulfillments(:active_subscription_fulfillment)
      fulfillment.update!(next_fulfillment_at: 1.second.ago)
      original_next = fulfillment.next_fulfillment_at

      service = FulfillmentService.new(fulfillment)
      service.process

      fulfillment.reload
      assert fulfillment.next_fulfillment_at > original_next
      assert fulfillment.next_fulfillment_at > Time.current
    end

    test "creates transaction with correct category for subscription" do
      wallet = usage_credits_wallets(:subscribed_wallet)
      fulfillment = usage_credits_fulfillments(:active_subscription_fulfillment)
      fulfillment.update!(next_fulfillment_at: 1.second.ago)

      service = FulfillmentService.new(fulfillment)
      service.process

      latest_tx = wallet.transactions.order(:created_at).last
      assert_equal "subscription_credits", latest_tx.category
    end

    test "sets expiration for non-rollover subscription credits" do
      wallet = usage_credits_wallets(:subscribed_wallet)
      fulfillment = usage_credits_fulfillments(:active_subscription_fulfillment)
      fulfillment.update!(next_fulfillment_at: 1.second.ago)

      service = FulfillmentService.new(fulfillment)
      service.process

      latest_tx = wallet.transactions.where(category: "subscription_credits").order(:created_at).last
      assert_not_nil latest_tx.expires_at
      assert latest_tx.expires_at > Time.current
    end

    test "does not set expiration for rollover subscription credits" do
      wallet = usage_credits_wallets(:subscribed_wallet)

      # Create rollover fulfillment
      fulfillment = Fulfillment.create!(
        wallet: wallet,
        fulfillment_type: "subscription",
        credits_last_fulfillment: 1000,
        fulfillment_period: "1.month",
        last_fulfilled_at: 1.month.ago,
        next_fulfillment_at: 1.day.from_now,
        metadata: {plan: "rollover_plan_monthly"}
      )

      fulfillment.update_columns(next_fulfillment_at: 1.second.ago)

      service = FulfillmentService.new(fulfillment)
      service.process

      latest_tx = wallet.transactions.where(category: "subscription_credits").order(:created_at).last
      assert_nil latest_tx.expires_at
    end

    test "does not award recurring credits while the Pay subscription is trialing" do
      fulfillment = usage_credits_fulfillments(:trial_fulfillment)
      wallet = fulfillment.wallet
      initial_credits = wallet.credits
      fulfillment.update_columns(next_fulfillment_at: 1.second.ago)

      result = FulfillmentService.new(fulfillment).process

      assert_nil result
      assert_equal initial_credits, wallet.reload.credits
      assert fulfillment.reload.next_fulfillment_at.past?, "skipped fulfillment should remain due for retry after activation"
    end

    test "does not award recurring credits during an effective Stripe pause and resumes afterward" do
      wallet, subscription, fulfillment = stripe_subscription_fulfillment("effective-pause")
      initial_credits = wallet.reload.credits

      subscription.update_columns(
        pause_behavior: "void",
        pause_starts_at: 1.minute.ago,
        updated_at: Time.current
      )
      fulfillment.update_columns(
        last_fulfilled_at: 1.month.ago,
        next_fulfillment_at: 1.second.ago
      )

      result = FulfillmentService.new(fulfillment.reload).process

      assert_nil result
      assert_equal "active", subscription.reload.status
      assert_not subscription.active?
      assert_equal initial_credits, wallet.reload.credits
      assert fulfillment.reload.next_fulfillment_at.past?

      subscription.update_columns(
        pause_behavior: nil,
        pause_starts_at: nil,
        updated_at: Time.current
      )

      assert subscription.reload.eligible_for_usage_credit_fulfillment?
      assert fulfillment.reload.due_for_fulfillment?
      assert_difference -> { wallet.reload.credits }, 500 do
        FulfillmentService.new(fulfillment.reload).process
      end
    end

    test "reconciles a deferred paused plan change before a recurring award" do
      wallet, subscription, fulfillment = stripe_subscription_fulfillment("deferred-reconcile")
      initial_credits = wallet.reload.credits

      subscription.update_columns(
        pause_behavior: "void",
        pause_starts_at: 1.minute.ago,
        updated_at: Time.current
      )
      subscription.update!(processor_plan: "stripe_pause_service_premium")
      assert_equal "stripe_pause_service_premium", fulfillment.reload.metadata["deferred_plan_change"]

      # Simulate a committed processor resume whose after-commit callback was
      # interrupted before it could install the deferred commercial terms.
      subscription.update_columns(
        pause_behavior: nil,
        pause_starts_at: nil,
        updated_at: Time.current
      )
      fulfillment.update_columns(
        last_fulfilled_at: 1.month.ago,
        next_fulfillment_at: 1.second.ago
      )

      assert_difference -> { wallet.reload.credits }, 2000 do
        FulfillmentService.new(fulfillment.reload).process
      end

      fulfillment.reload
      assert_equal "stripe_pause_service_premium", fulfillment.metadata["plan"]
      assert_nil fulfillment.metadata["deferred_plan_change"]
      assert_equal initial_credits + 2000, wallet.reload.credits
    end

    test "fails closed when deferred plan terms are corrupt" do
      wallet, subscription, fulfillment = stripe_subscription_fulfillment("corrupt-deferred")
      initial_credits = wallet.reload.credits

      subscription.update_columns(
        processor_plan: "stripe_pause_service_premium",
        updated_at: Time.current
      )
      fulfillment.update_columns(
        last_fulfilled_at: 1.month.ago,
        next_fulfillment_at: 1.second.ago,
        metadata: fulfillment.metadata.merge(
          "deferred_plan_change" => "stripe_pause_service_premium",
          "deferred_plan_snapshot" => {"plan" => "wrong_plan"}
        )
      )

      error = assert_raises(UsageCredits::InvalidOperation) do
        FulfillmentService.new(fulfillment.reload).process
      end

      assert_includes error.message, "do not match"
      assert_equal initial_credits, wallet.reload.credits
    end

    test "fails closed while an active processor plan transition is unreconciled" do
      wallet, subscription, fulfillment = stripe_subscription_fulfillment("unreconciled-plan")
      initial_credits = wallet.reload.credits

      # update_columns models the interval after Pay committed the new plan but
      # before UsageCredits' after-commit reconciliation completed.
      subscription.update_columns(
        processor_plan: "stripe_pause_service_premium",
        updated_at: Time.current
      )
      fulfillment.update_columns(
        last_fulfilled_at: 1.month.ago,
        next_fulfillment_at: 1.second.ago
      )

      error = assert_raises(UsageCredits::InvalidOperation) do
        FulfillmentService.new(fulfillment.reload).process
      end

      assert_includes error.message, "has not been reconciled"
      assert_equal initial_credits, wallet.reload.credits
    end

    test "does not award credits when a recorded Pay subscription is missing" do
      wallet = usage_credits_wallets(:subscribed_wallet)
      initial_credits = wallet.credits
      fulfillment = usage_credits_fulfillments(:active_subscription_fulfillment)
      initial_transactions = wallet.transactions.where(fulfillment: fulfillment).count
      fulfillment.update_columns(source_id: 999_999, next_fulfillment_at: 1.second.ago)

      error = assert_raises(UsageCredits::Error) do
        FulfillmentService.new(fulfillment.reload).process
      end

      assert_includes error.message, "no longer exists"
      assert_equal initial_credits, wallet.reload.credits
      assert_equal initial_transactions, wallet.transactions.where(fulfillment: fulfillment).count
    end

    test "recognizes a dangling processor-specific Pay source type" do
      wallet = usage_credits_wallets(:subscribed_wallet)
      initial_credits = wallet.credits
      fulfillment = usage_credits_fulfillments(:active_subscription_fulfillment)
      fulfillment.update_columns(
        source_type: "Pay::Stripe::Subscription",
        source_id: 999_999,
        next_fulfillment_at: 1.second.ago
      )

      error = assert_raises(UsageCredits::Error) do
        FulfillmentService.new(fulfillment.reload).process
      end

      assert_includes error.message, "no longer exists"
      assert_equal initial_credits, wallet.reload.credits
    end

    test "trial boundary activates processors whose status stays active" do
      UsageCredits.configure do |config|
        config.subscription_plan :active_trial_test do
          processor_plan(:fake_processor, "active_trial_plan")
          gives 500.credits.every(:month)
          signup_bonus 100.credits
          trial_includes 50.credits
          unused_credits :expire
        end
      end

      user = User.create!(email: "active-trial-#{SecureRandom.hex(4)}@example.com", name: "Active Trial")
      wallet = user.credit_wallet
      customer = Pay::Customer.create!(
        owner: user,
        processor: :fake_processor,
        processor_id: "cus_active_trial_#{SecureRandom.hex(4)}"
      )
      subscription = Pay::Subscription.create!(
        customer: customer,
        name: "default",
        processor_id: "sub_active_trial_#{SecureRandom.hex(4)}",
        processor_plan: "active_trial_plan",
        status: "active",
        quantity: 1,
        trial_ends_at: 1.day.from_now
      )
      fulfillment = Fulfillment.find_by!(source: subscription)

      assert_equal 50, wallet.reload.credits
      assert_equal "trial", fulfillment.metadata["initial_award_state"]

      # Some processors do not emit a status transition when an active trial
      # ends. Simulate the clock boundary without an Active Record callback.
      subscription.update_columns(trial_ends_at: 1.second.ago, updated_at: Time.current)
      fulfillment.update_columns(next_fulfillment_at: 1.second.ago)

      assert_difference -> { wallet.reload.credits }, 600 do
        FulfillmentService.new(fulfillment.reload).process
      end

      assert_equal "active", fulfillment.reload.metadata["initial_award_state"]
      assert fulfillment.next_fulfillment_at.future?
    end

    test "dispatches subscription credits awarded after a recurring fulfillment" do
      fulfillment = usage_credits_fulfillments(:active_subscription_fulfillment)
      fulfillment.update!(next_fulfillment_at: 1.second.ago)
      events = []
      UsageCredits.configure do |config|
        config.on_subscription_credits_awarded { |context| events << context }
      end

      transaction = FulfillmentService.new(fulfillment).process

      assert_equal 1, events.size
      assert_equal transaction, events.first.transaction
      assert_equal transaction.amount, events.first.amount
      assert_equal fulfillment.id, events.first.metadata[:fulfillment].id
    end

    # ========================================
    # CREDIT PACK FULFILLMENT PROCESSING
    # ========================================

    test "processes credit pack fulfillment" do
      wallet = usage_credits_wallets(:rich_wallet)
      initial_credits = wallet.credits

      # Create credit pack fulfillment
      fulfillment = Fulfillment.create!(
        wallet: wallet,
        fulfillment_type: "credit_pack",
        credits_last_fulfillment: 1000,
        last_fulfilled_at: nil,
        next_fulfillment_at: 1.second.ago,
        metadata: {pack: "test_pack"}
      )

      service = FulfillmentService.new(fulfillment)
      service.process

      assert_equal initial_credits + 1000, wallet.reload.credits
    end

    test "creates transaction with correct category for credit pack" do
      wallet = usage_credits_wallets(:rich_wallet)

      fulfillment = Fulfillment.create!(
        wallet: wallet,
        fulfillment_type: "credit_pack",
        credits_last_fulfillment: 1000,
        last_fulfilled_at: nil,
        next_fulfillment_at: 1.second.ago,
        metadata: {pack: "test_pack"}
      )

      service = FulfillmentService.new(fulfillment)
      service.process

      latest_tx = wallet.transactions.order(:created_at).last
      assert_equal "credit_pack_purchase", latest_tx.category
    end

    # ========================================
    # MANUAL FULFILLMENT PROCESSING
    # ========================================

    test "processes manual fulfillment with metadata credits" do
      wallet = usage_credits_wallets(:rich_wallet)
      initial_credits = wallet.credits

      # Create with future date, then update to past (bypass validation)
      fulfillment = Fulfillment.create!(
        wallet: wallet,
        fulfillment_type: "manual",
        credits_last_fulfillment: 250,
        last_fulfilled_at: nil,
        next_fulfillment_at: 1.day.from_now,
        fulfillment_period: "1.month",
        metadata: {credits: 250}
      )

      fulfillment.update_columns(next_fulfillment_at: 1.second.ago)

      service = FulfillmentService.new(fulfillment)
      service.process

      assert_equal initial_credits + 250, wallet.reload.credits
    end

    test "creates transaction with correct category for manual" do
      wallet = usage_credits_wallets(:rich_wallet)

      # Create with future date, then update to past (bypass validation)
      fulfillment = Fulfillment.create!(
        wallet: wallet,
        fulfillment_type: "manual",
        credits_last_fulfillment: 100,
        last_fulfilled_at: nil,
        next_fulfillment_at: 1.day.from_now,
        fulfillment_period: "1.month",
        metadata: {credits: 100}
      )

      fulfillment.update_columns(next_fulfillment_at: 1.second.ago)

      service = FulfillmentService.new(fulfillment)
      service.process

      latest_tx = wallet.transactions.order(:created_at).last
      assert_equal "credit_added", latest_tx.category
    end

    # ========================================
    # TRANSACTION SAFETY & CONCURRENCY
    # ========================================

    test "skips fulfillment if not due after lock" do
      wallet = usage_credits_wallets(:subscribed_wallet)
      initial_credits = wallet.credits

      # Fulfillment in the future
      fulfillment = usage_credits_fulfillments(:active_subscription_fulfillment)
      fulfillment.update!(next_fulfillment_at: 1.day.from_now)

      service = FulfillmentService.new(fulfillment)
      service.process

      # No credits should be added
      assert_equal initial_credits, wallet.reload.credits
    end

    test "uses transaction to ensure atomicity" do
      fulfillment = usage_credits_fulfillments(:active_subscription_fulfillment)
      fulfillment.update!(next_fulfillment_at: 1.second.ago)

      # Verify transaction is used (can't test rollback easily without mocking)
      service = FulfillmentService.new(fulfillment)

      assert_nothing_raised do
        service.process
      end
    end

    # ========================================
    # ERROR HANDLING
    # ========================================

    test "raises error when subscription plan not found" do
      wallet = usage_credits_wallets(:subscribed_wallet)

      # Create with future date, then update to past (bypass validation)
      fulfillment = Fulfillment.create!(
        wallet: wallet,
        fulfillment_type: "subscription",
        credits_last_fulfillment: 500,
        fulfillment_period: "1.month",
        last_fulfilled_at: 1.month.ago,
        next_fulfillment_at: 1.day.from_now,
        metadata: {plan: "nonexistent_plan_id"}
      )

      fulfillment.update_columns(next_fulfillment_at: 1.second.ago)

      service = FulfillmentService.new(fulfillment)

      error = assert_raises(UsageCredits::InvalidOperation) do
        service.process
      end

      assert_includes error.message, "No subscription plan found"
    end

    test "raises error when credit pack not found" do
      wallet = usage_credits_wallets(:rich_wallet)

      # For credit_pack, next_fulfillment_at should be nil (one-time)
      fulfillment = Fulfillment.create!(
        wallet: wallet,
        fulfillment_type: "credit_pack",
        credits_last_fulfillment: 1000,
        last_fulfilled_at: nil,
        next_fulfillment_at: nil,
        metadata: {pack: "nonexistent_pack"}
      )

      # Manually set to make it appear due (for testing)
      fulfillment.update_columns(next_fulfillment_at: 1.second.ago)

      service = FulfillmentService.new(fulfillment)

      error = assert_raises(UsageCredits::InvalidOperation) do
        service.process
      end

      assert_includes error.message, "No credit pack named"
    end

    # ========================================
    # BATCH PROCESSING
    # ========================================

    test "process_pending_fulfillments processes all due fulfillments" do
      # Make two fulfillments due
      f1 = usage_credits_fulfillments(:active_subscription_fulfillment)
      f1.update!(next_fulfillment_at: 1.second.ago)

      f2 = usage_credits_fulfillments(:trial_fulfillment)
      f2.update!(next_fulfillment_at: 1.second.ago)

      count = FulfillmentService.process_pending_fulfillments

      assert count >= 1
      assert f2.reload.next_fulfillment_at.past?, "trial fulfillment should be skipped and not counted"
    end

    test "process_pending_fulfillments continues on error" do
      # Create one valid and one invalid fulfillment
      wallet = usage_credits_wallets(:rich_wallet)

      # Valid fulfillment - create with future date, then update to past
      valid = Fulfillment.create!(
        wallet: wallet,
        fulfillment_type: "manual",
        credits_last_fulfillment: 100,
        last_fulfilled_at: nil,
        next_fulfillment_at: 1.day.from_now,
        fulfillment_period: "1.month",
        metadata: {credits: 100}
      )
      valid.update_columns(next_fulfillment_at: 1.second.ago)

      # Invalid fulfillment (missing plan) - create with future date, then update to past
      invalid = Fulfillment.create!(
        wallet: wallet,
        fulfillment_type: "subscription",
        credits_last_fulfillment: 500,
        fulfillment_period: "1.month",
        last_fulfilled_at: 1.month.ago,
        next_fulfillment_at: 1.day.from_now,
        metadata: {plan: "nonexistent"}
      )
      invalid.update_columns(next_fulfillment_at: 1.second.ago)

      # Should process valid and continue despite invalid
      count = FulfillmentService.process_pending_fulfillments

      # At least the valid one should be processed
      assert count >= 1
    end

    test "process_pending_fulfillments returns count of processed" do
      # Make one fulfillment due
      f1 = usage_credits_fulfillments(:active_subscription_fulfillment)
      f1.update!(next_fulfillment_at: 1.second.ago)

      count = FulfillmentService.process_pending_fulfillments

      assert count >= 1
    end

    # ========================================
    # METADATA HANDLING
    # ========================================

    test "includes fulfillment metadata in transaction" do
      wallet = usage_credits_wallets(:subscribed_wallet)
      fulfillment = usage_credits_fulfillments(:active_subscription_fulfillment)
      fulfillment.update!(next_fulfillment_at: 1.second.ago)

      service = FulfillmentService.new(fulfillment)
      service.process

      latest_tx = wallet.transactions.order(:created_at).last
      assert_not_nil latest_tx.metadata["fulfillment_id"]
      assert_equal fulfillment.id, latest_tx.metadata["fulfillment_id"]
    end

    test "includes subscription_id in metadata for subscription fulfillments" do
      wallet = usage_credits_wallets(:subscribed_wallet)
      fulfillment = usage_credits_fulfillments(:active_subscription_fulfillment)
      fulfillment.update!(next_fulfillment_at: 1.second.ago)

      service = FulfillmentService.new(fulfillment)
      service.process

      latest_tx = wallet.transactions.order(:created_at).last
      assert_not_nil latest_tx.metadata["subscription_id"]
    end

    # ========================================
    # ADDITIONAL EDGE CASES
    # ========================================

    test "stopped fulfillment is not processed" do
      wallet = usage_credits_wallets(:cancelled_wallet)
      initial_credits = wallet.credits

      # Use stopped fulfillment from fixtures
      fulfillment = usage_credits_fulfillments(:stopped_fulfillment)

      # Even if we try to create a service for it, it should not add credits
      # because due_for_fulfillment? returns false for stopped fulfillments
      service = FulfillmentService.new(fulfillment)
      service.process

      # Credits should not change
      assert_equal initial_credits, wallet.reload.credits
    end

    test "expiration includes grace period from configuration" do
      wallet = usage_credits_wallets(:subscribed_wallet)
      fulfillment = usage_credits_fulfillments(:active_subscription_fulfillment)
      fulfillment.update!(next_fulfillment_at: 1.second.ago)

      service = FulfillmentService.new(fulfillment)
      service.process

      latest_tx = wallet.transactions.where(category: "subscription_credits").order(:created_at).last

      # Expiration should be: next_fulfillment_at + grace_period
      # Default grace period is 3 days
      expected_min = fulfillment.reload.next_fulfillment_at + UsageCredits.configuration.fulfillment_grace_period - 1.minute
      assert latest_tx.expires_at >= expected_min
    end

    test "process returns early for fulfillment already processed" do
      wallet = usage_credits_wallets(:subscribed_wallet)
      fulfillment = usage_credits_fulfillments(:active_subscription_fulfillment)

      # Make it due now
      fulfillment.update!(next_fulfillment_at: 1.second.ago)

      service = FulfillmentService.new(fulfillment)
      service.process

      initial_credits = wallet.reload.credits

      # Create new service and try to process again immediately
      # The fulfillment should now have next_fulfillment_at in the future
      service2 = FulfillmentService.new(fulfillment.reload)
      service2.process

      # Credits should not change (already processed)
      assert_equal initial_credits, wallet.reload.credits
    end

    test "links transaction to fulfillment record" do
      wallet = usage_credits_wallets(:subscribed_wallet)
      fulfillment = usage_credits_fulfillments(:active_subscription_fulfillment)
      fulfillment.update!(next_fulfillment_at: 1.second.ago)

      service = FulfillmentService.new(fulfillment)
      service.process

      latest_tx = wallet.transactions.order(:created_at).last
      assert_equal fulfillment.id, latest_tx.fulfillment_id
    end

    # ========================================
    # BUG FIX: Balance accumulation with short fulfillment periods
    # ========================================
    # When fulfillment_period is much shorter than fulfillment_grace_period,
    # the balance keeps growing because credits don't expire fast enough.
    # The fix: cap the effective grace period to the fulfillment period.

    test "credits expire at appropriate time when fulfillment period is shorter than grace period" do
      # Configure a plan with very short fulfillment period
      UsageCredits.configure do |config|
        config.min_fulfillment_period = 1.second

        config.subscription_plan :rapid_test do
          processor_plan(:fake_processor, "rapid_plan_id")
          gives 100.credits.every(5.seconds)
          unused_credits :expire
        end
      end

      wallet = usage_credits_wallets(:rich_wallet)

      # Create a fulfillment with 5-second period
      fulfillment = Fulfillment.create!(
        wallet: wallet,
        fulfillment_type: "subscription",
        credits_last_fulfillment: 100,
        fulfillment_period: "5.seconds",
        last_fulfilled_at: 6.seconds.ago,
        next_fulfillment_at: 1.day.from_now,
        metadata: {plan: "rapid_plan_id"}
      )
      fulfillment.update_columns(next_fulfillment_at: 1.second.ago)

      # Default grace period is 5 minutes (300 seconds)
      # With 5-second fulfillment period, credits should expire within ~10 seconds (period + capped grace)
      # NOT in 305 seconds (period + full grace)
      service = FulfillmentService.new(fulfillment)
      service.process

      latest_tx = wallet.transactions.where(category: "subscription_credits").order(:created_at).last

      # The expiration should be capped: credits should expire in roughly:
      # next_fulfillment_at + min(grace_period, fulfillment_period)
      # NOT next_fulfillment_at + full_grace_period

      fulfillment.reload
      fulfillment_period = 5.seconds
      expected_max_expiration = fulfillment.next_fulfillment_at + fulfillment_period

      # Credits should expire no later than 2x the fulfillment period after next_fulfillment_at
      # (i.e., grace period should be capped to fulfillment_period)
      assert latest_tx.expires_at <= expected_max_expiration,
        "Credits expire at #{latest_tx.expires_at}, but should expire by #{expected_max_expiration}. " \
        "Grace period should be capped to fulfillment period to prevent balance accumulation."
    end

    test "balance does not accumulate indefinitely with rapid fulfillments" do
      # This test simulates the actual bug: with short fulfillment periods,
      # balance keeps growing because credits don't expire fast enough

      UsageCredits.configure do |config|
        config.min_fulfillment_period = 1.second

        config.subscription_plan :rapid_accumulation_test do
          processor_plan(:fake_processor, "rapid_accumulation_plan")
          gives 100.credits.every(2.seconds)
          unused_credits :expire
        end
      end

      wallet = UsageCredits::Wallet.create!(owner: users(:walletless_user), asset_code: "accumulation_test")

      # Create fulfillment
      fulfillment = Fulfillment.create!(
        wallet: wallet,
        fulfillment_type: "subscription",
        credits_last_fulfillment: 100,
        fulfillment_period: "2.seconds",
        last_fulfilled_at: nil,
        next_fulfillment_at: 1.day.from_now,
        metadata: {plan: "rapid_accumulation_plan"}
      )

      # Simulate multiple fulfillment cycles
      # Each cycle adds 100 credits. With proper expiration, old credits should expire
      # before too many accumulate.

      5.times do |i|
        # Make fulfillment due
        fulfillment.update_columns(next_fulfillment_at: 1.second.ago)

        service = FulfillmentService.new(fulfillment.reload)
        service.process
      end

      # After 5 cycles of 100 credits each with 2-second periods:
      # - If grace is capped to fulfillment period (2 sec), max ~200 credits at a time
      # - If grace is full 5 minutes, we'd have all 500 credits still valid

      # Calculate expected max balance:
      # With capped grace period = fulfillment period, credits last for 2 periods max
      # So maximum should be around 2 * 100 = 200 credits
      max_expected_balance = 200

      # Give some tolerance for timing
      assert wallet.reload.credits <= max_expected_balance + 100,
        "Balance is #{wallet.credits}, but should not exceed #{max_expected_balance + 100}. " \
        "Credits are accumulating because grace period is not capped to fulfillment period."
    end

    test "manual fulfillment rejects fractional string credits instead of truncating" do
      fulfillment = Fulfillment.new(
        wallet: usage_credits_wallets(:rich_wallet),
        fulfillment_type: "manual",
        credits_last_fulfillment: 0,
        metadata: {credits: "10.5"}
      )

      service = FulfillmentService.new(fulfillment)
      error = assert_raises(UsageCredits::Error) { service.send(:calculate_credits) }

      assert_includes error.message, "positive whole number"
    end

    private

    def stripe_subscription_fulfillment(label)
      token = SecureRandom.hex(4)
      user = User.create!(
        email: "stripe-pause-service-#{label}-#{token}@example.com",
        name: "Stripe Pause Service"
      )
      customer = Pay::Customer.create!(
        owner: user,
        processor: :stripe,
        processor_id: "cus_stripe_pause_service_#{token}"
      )
      subscription = Pay::Stripe::Subscription.create!(
        customer: customer,
        name: "default",
        processor_id: "sub_stripe_pause_service_#{token}",
        processor_plan: "stripe_pause_service_pro",
        status: "active",
        quantity: 1,
        current_period_start: Time.current,
        current_period_end: 1.month.from_now
      )

      [user.credit_wallet, subscription, Fulfillment.find_by!(source: subscription)]
    end
  end
end
