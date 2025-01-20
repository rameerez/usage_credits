# frozen_string_literal: true

require "test_helper"

module UsageCredits
  class CreditSystemTest < ActiveSupport::TestCase
    setup do
      @user = users(:default)
      @wallet = @user.credit_wallet
    end

    #######################
    # Core Wallet System #
    #######################

    test "user has a wallet automatically created" do
      new_user = users(:no_wallet)
      assert_not_nil new_user.credit_wallet
      assert_instance_of UsageCredits::Wallet, new_user.credit_wallet
    end

    test "wallet starts with zero balance" do
      assert_equal 0, @user.credits
      assert_equal 0, @wallet.balance
    end

    test "credits and balance are always integers" do
      @user.give_credits(100, reason: "signup")
      assert_kind_of Integer, @user.credits
      assert_kind_of Integer, @wallet.balance
    end

    test "wallet balance matches user credits" do
      @user.give_credits(100, reason: "signup")
      assert_equal @wallet.balance, @user.credits
    end

    #######################
    # Credit Management #
    #######################

    test "can give credits with a reason" do
      @user.give_credits(100, reason: "signup")
      assert_equal 100, @user.credits

      transaction = @user.credit_history.last
      assert_equal "signup", transaction.metadata["reason"]
      assert_equal "signup_bonus", transaction.category
    end

    test "can add credits with metadata" do
      @wallet.add_credits(100, metadata: { source: "welcome_bonus" })
      transaction = @user.credit_history.last
      assert_equal "welcome_bonus", transaction.metadata["source"]
    end

    test "cannot give negative credits" do
      assert_raises(ArgumentError) do
        @user.give_credits(-100, reason: "signup")
      end
      assert_equal 0, @user.credits
    end

    test "credits must be integers" do
      assert_raises(ActiveRecord::RecordInvalid) do
        @user.give_credits(10.5, reason: "signup")
      end
    end

    test "can give credits with multiple reasons" do
      @user.give_credits(100, reason: "signup")
      @user.give_credits(50, reason: "referral")
      assert_equal 150, @user.credits

      reasons = @user.credit_history
        .order(:created_at)
        .pluck(Arel.sql("metadata->>'reason'"))

      assert_equal ["signup", "referral"], reasons
    end

    ######################
    # Operation Spending #
    ######################

    test "can check if user has enough credits" do
      @user.give_credits(100, reason: "signup")
      assert @user.has_enough_credits_to?(:test_operation)
      assert_not @user.has_enough_credits_to?(:expensive_operation)
    end

    test "can estimate operation cost" do
      cost = @user.estimate_credits_to(:test_operation)
      assert_equal 1, cost
    end

    test "can estimate operation cost with parameters" do
      cost = @user.estimate_credits_to(:process_image, size: 5.megabytes)
      assert_equal 15, cost # 10 base + 5 MB * 1 credit/MB
    end

    test "can spend credits on operation" do
      @user.give_credits(100, reason: "signup")
      @user.spend_credits_on(:test_operation)
      assert_equal 99, @user.credits
    end

    test "cannot spend more credits than available" do
      @user.give_credits(1, reason: "signup")
      assert_raises(InsufficientCredits) do
        @user.spend_credits_on(:expensive_operation)
      end
      assert_equal 1, @user.credits
    end

    test "spending credits is atomic" do
      @user.give_credits(10, reason: "signup")
      assert_raises(StandardError) do
        @user.spend_credits_on(:test_operation) do
          raise StandardError, "Operation failed"
        end
      end
      assert_equal 10, @user.credits, "Credits should not be spent if operation fails"
    end

    test "spending credits with parameters" do
      @user.give_credits(100, reason: "signup")
      @user.spend_credits_on(:process_image, size: 5.megabytes)
      assert_equal 85, @user.credits # 100 - (10 base + 5 MB * 1 credit/MB)
    end

    test "operation validation prevents spending" do
      @user.give_credits(1000, reason: "signup")
      assert_raises(InvalidOperation) do
        @user.spend_credits_on(:process_image, size: 101.megabytes)
      end
      assert_equal 1000, @user.credits, "Credits should not be spent if validation fails"
    end

    ####################
    # History Tracking #
    ####################

    test "tracks credit history" do
      @user.give_credits(100, reason: "signup")
      @user.spend_credits_on(:test_operation)

      assert_equal 2, @user.credit_history.count
      assert_equal ["signup_bonus", "operation_charge"], @user.credit_history.pluck(:category)
      assert_equal [100, -1], @user.credit_history.pluck(:amount)
    end

    test "credit history includes reason" do
      @user.give_credits(100, reason: "signup")
      transaction = @user.credit_history.last

      assert_equal "signup_bonus", transaction.category
      assert_equal 100, transaction.amount
      assert_equal "signup", transaction.metadata["reason"]
    end

    test "operation charges include detailed metadata" do
      @user.give_credits(100, reason: "signup")
      @user.spend_credits_on(:test_operation)

      charge = @user.credit_history.operation_charges.last
      metadata = charge.metadata

      assert_equal "test_operation", metadata["operation"]
      assert_equal 1, metadata["cost"]
      assert_not_nil metadata["executed_at"]
      assert_not_nil charge.metadata["gem_version"]
    end

    test "can filter history by category" do
      @user.give_credits(100, reason: "signup")
      @user.spend_credits_on(:test_operation)

      assert_equal 1, @user.credit_history.by_category(:signup_bonus).count
      assert_equal 1, @user.credit_history.by_category(:operation_charge).count
    end

    test "history is ordered chronologically" do
      @user.give_credits(100, reason: "first")
      @user.give_credits(50, reason: "second")

      reasons = @user.credit_history
        .pluck(Arel.sql("metadata->>'reason'"))

      assert_equal ["first", "second"], reasons
    end

    test "history includes all transaction details" do
      @user.give_credits(100, reason: "signup")
      @user.spend_credits_on(:test_operation)

      transaction = @user.credit_history.last
      assert_not_nil transaction.created_at
      assert_not_nil transaction.updated_at
      assert_not_nil transaction.id
      assert_equal @wallet.id, transaction.wallet_id
    end

    ######################
    # Low Balance Alerts #
    ######################

    test "triggers low balance alert when threshold is reached" do
      original_threshold = UsageCredits.configuration.low_balance_threshold

      UsageCredits.configure do |config|
        config.low_balance_threshold = 50
        config.on_low_balance do |user|
          @alert_triggered = true
          assert_equal @user, user
        end
      end

      @alert_triggered = false
      @user.give_credits(100, reason: "signup")

      # Spend 60 credits to drop below the 50 credit threshold
      @user.spend_credits_on(:test_operation, cost: 60)

      assert @alert_triggered, "Low balance alert should have been triggered"

      # Reset configuration
      UsageCredits.configure do |config|
        config.low_balance_threshold = original_threshold
      end
    end

    test "does not trigger low balance alert when no threshold set" do
      original_threshold = UsageCredits.configuration.low_balance_threshold

      UsageCredits.configure do |config|
        config.low_balance_threshold = nil
        config.on_low_balance do |user|
          @alert_triggered = true
        end
      end

      @alert_triggered = false
      @user.give_credits(100, reason: "signup")
      @user.spend_credits_on(:test_operation)

      assert_not @alert_triggered, "Low balance alert should not have been triggered"

      # Reset configuration
      UsageCredits.configure do |config|
        config.low_balance_threshold = original_threshold
      end
    end

    test "low balance threshold must be positive" do
      assert_raises(ArgumentError) do
        UsageCredits.configure do |config|
          config.low_balance_threshold = -10
        end
      end
    end

    ####################
    # Credit Expiration #
    ####################

    test "can add credits with expiration" do
      expiry_time = 1.day.from_now
      @wallet.add_credits(100, expires_at: expiry_time)

      transaction = @user.credit_history.last
      assert_equal expiry_time.to_i, transaction.expires_at.to_i
    end

    test "expired credits are marked as such" do
      @wallet.add_credits(100, expires_at: 1.day.ago)
      transaction = @user.credit_history.last

      assert transaction.expired?
    end

    test "future expiring credits are not marked as expired" do
      @wallet.add_credits(100, expires_at: 1.day.from_now)
      transaction = @user.credit_history.last

      assert_not transaction.expired?
    end

    test "credits without expiration are never marked as expired" do
      @wallet.add_credits(100)
      transaction = @user.credit_history.last

      assert_not transaction.expired?
    end

    #########################
    # Credit Formatting #
    #########################

    test "can format credits with custom formatter" do
      original_formatter = UsageCredits.configuration.credit_formatter

      UsageCredits.configure do |config|
        config.format_credits do |amount|
          "#{amount} awesome credits"
        end
      end

      @user.give_credits(100, reason: "signup")
      transaction = @user.credit_history.last

      assert_equal "+100 awesome credits", transaction.formatted_amount

      # Reset formatter
      UsageCredits.configure do |config|
        config.format_credits(&original_formatter)
      end
    end

    test "negative amounts are properly formatted" do
      @user.give_credits(100, reason: "signup")
      @user.spend_credits_on(:test_operation)

      transaction = @user.credit_history.last
      assert_match /^-/, transaction.formatted_amount
    end

    test "positive amounts include plus sign" do
      @user.give_credits(100, reason: "signup")
      transaction = @user.credit_history.last
      assert_match /^\+/, transaction.formatted_amount
    end
  end
end
