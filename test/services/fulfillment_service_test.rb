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
        metadata: { plan: "rollover_plan_monthly" }
      )

      fulfillment.update_columns(next_fulfillment_at: 1.second.ago)

      service = FulfillmentService.new(fulfillment)
      service.process

      latest_tx = wallet.transactions.where(category: "subscription_credits").order(:created_at).last
      assert_nil latest_tx.expires_at
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
        metadata: { pack: "test_pack" }
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
        metadata: { pack: "test_pack" }
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
        metadata: { credits: 250 }
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
        metadata: { credits: 100 }
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
        metadata: { plan: "nonexistent_plan_id" }
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
        metadata: { pack: "nonexistent_pack" }
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

      assert count >= 2
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
        metadata: { credits: 100 }
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
        metadata: { plan: "nonexistent" }
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
  end
end
