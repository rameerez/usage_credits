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

    test "wallet balance matches user credits upon funding" do
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
      assert_raises(ArgumentError) do
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
      assert_not @user.has_enough_credits_to?(:absurdly_expensive_operation)
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
      @user.spend_credits_on(:mb_op, mb: 60)

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

    ########################
    # Operation Definition #
    ########################

    test "operation costs must be whole numbers" do
      assert_raises(ArgumentError) do
        UsageCredits.configure do |config|
          operation :invalid_op do
            cost 10.5.credits
          end
        end
      end
    end

    test "operation rates must be whole numbers" do
      assert_raises(ArgumentError) do
        UsageCredits.configure do |config|
          operation :invalid_op do
            cost 1.5.credits_per(:mb)
          end
        end
      end
    end

    test "operation metadata is included in charges" do
      UsageCredits.configure do |config|
        operation :meta_op do
          cost 10.credits
          meta category: :test, description: "Test operation"
        end
      end

      @user.give_credits(100, reason: "test")
      @user.spend_credits_on(:meta_op)

      charge = @user.credit_history.operation_charges.last
      assert_equal "test", charge.metadata["category"]
      assert_equal "Test operation", charge.metadata["description"]
    end

    test "operation validation prevents invalid parameters" do
      UsageCredits.configure do |config|
        operation :validated_op do
          cost 10.credits
          validate ->(params) { params[:value] > 0 }, "Value must be positive"
        end
      end

      @user.give_credits(100, reason: "test")

      assert_raises(InvalidOperation, "Value must be positive") do
        @user.spend_credits_on(:validated_op, value: -1)
      end

      assert_equal 100, @user.credits, "Credits should not be spent if validation fails"
    end

    test "operation can have multiple validations" do
      UsageCredits.configure do |config|
        operation :multi_validated_op do
          cost 10.credits
          validate ->(params) { params[:value] > 0 }, "Value must be positive"
          validate ->(params) { params[:value] < 100 }, "Value must be less than 100"
        end
      end

      @user.give_credits(100, reason: "test")

      assert_raises(InvalidOperation, "Value must be less than 100") do
        @user.spend_credits_on(:multi_validated_op, value: 150)
      end

      assert_nothing_raised do
        @user.spend_credits_on(:multi_validated_op, value: 50)
      end
    end

    test "operation metadata is included in transaction" do
      UsageCredits.configure do |config|
        operation :meta_op do
          cost 10.credits
          meta category: :test,
               description: "Test operation",
               version: "1.0"
        end
      end

      @user.give_credits(100, reason: "test")
      @user.spend_credits_on(:meta_op)

      transaction = @user.credit_history.operation_charges.last
      assert_equal "test", transaction.metadata["category"]
      assert_equal "Test operation", transaction.metadata["description"]
      assert_equal "1.0", transaction.metadata["version"]
    end

    test "operation cost can depend on parameters" do
      UsageCredits.configure do |config|
        operation :variable_op do
          cost 10.credits + 2.credits_per(:units)
        end
      end

      @user.give_credits(100, reason: "test")

      # Test different unit amounts
      assert_equal 14, @user.estimate_credits_to(:variable_op, units: 2)
      assert_equal 20, @user.estimate_credits_to(:variable_op, units: 5)

      @user.spend_credits_on(:variable_op, units: 2)
      assert_equal 86, @user.credits # 100 - (10 + 2 * 2)
    end

    test "operation cost calculation handles edge cases" do
      UsageCredits.configure do |config|
        operation :edge_op do
          cost 10.credits + 1.credits_per(:mb)
        end
      end

      @user.give_credits(100, reason: "test")

      # Test zero units
      assert_equal 10, @user.estimate_credits_to(:edge_op, mb: 0)

      # Test fractional units (should round up)
      assert_equal 12, @user.estimate_credits_to(:edge_op, mb: 1.2)

      # Test large numbers
      assert_equal 1010, @user.estimate_credits_to(:edge_op, mb: 1000)
    end

    test "operation execution is tracked with timestamps" do
      @user.give_credits(100, reason: "test")

      time = 10.seconds.ago
      @user.spend_credits_on(:test_operation)

      transaction = @user.credit_history.operation_charges.last
      assert_not_nil transaction.metadata["executed_at"]
      assert Time.parse(transaction.metadata["executed_at"]) >= time
    end

    ########################
    # Rounding Behavior #
    ########################

    test "rounding strategy can be configured" do
      original_strategy = UsageCredits.configuration.rounding_strategy

      UsageCredits.configure do |config|
        operation :mb_variable_op do
          cost 1.credits_per(:mb)
        end
      end

      # Test rounding up
      UsageCredits.configuration.rounding_strategy = :ceil
      assert_equal 2, @user.estimate_credits_to(:mb_variable_op, mb: 1.1)

      # Test rounding down
      UsageCredits.configuration.rounding_strategy = :floor
      assert_equal 1, @user.estimate_credits_to(:mb_variable_op, mb: 1.1)

      # Test normal rounding
      UsageCredits.configuration.rounding_strategy = :round
      assert_equal 1, @user.estimate_credits_to(:mb_variable_op, mb: 1.1)
      assert_equal 2, @user.estimate_credits_to(:mb_variable_op, mb: 1.6)

      # Reset configuration
      UsageCredits.configuration.rounding_strategy = original_strategy
    end

    test "defaults to ceiling rounding when strategy is invalid" do
      original_strategy = UsageCredits.configuration.rounding_strategy

      UsageCredits.configure do |config|
        operation :variable_op do
          cost 1.credits_per(:mb)
        end
        config.rounding_strategy = :invalid
      end

      assert_equal 2, @user.estimate_credits_to(:variable_op, mb: 1.1)

      # Reset configuration
      UsageCredits.configuration.rounding_strategy = original_strategy
    end

    ########################
    # Unit Handling #
    ########################

    test "can handle different unit formats" do
      UsageCredits.configure do |config|
        operation :size_op do
          cost 1.credits_per(:mb)
        end
      end

      # Test direct MB specification
      assert_equal 5, @user.estimate_credits_to(:size_op, mb: 5)

      # Test byte conversion
      assert_equal 5, @user.estimate_credits_to(:size_op, size: 5.megabytes)

      # Test zero values
      assert_equal 0, @user.estimate_credits_to(:size_op, mb: 0)
      assert_equal 0, @user.estimate_credits_to(:size_op, size: 0)
    end

    test "accepts various unit names" do
      UsageCredits.configure do |config|
        operation :mb_op do
          cost 1.credits_per(:megabytes)
        end

        operation :kb_op do
          cost 1.credits_per(:kilobytes)
        end

        operation :gb_op do
          cost 1.credits_per(:gigabytes)
        end

        operation :unit_op do
          cost 1.credits_per(:units)
        end
      end

      assert_equal 5, @user.estimate_credits_to(:mb_op, mb: 5)
      assert_equal 5, @user.estimate_credits_to(:unit_op, units: 5)

      # Test direct unit parameter handling
      assert_equal 5, @user.estimate_credits_to(:mb_op, mb: 5)
      assert_equal 5, @user.estimate_credits_to(:mb_op, size_mb: 5)
      assert_equal 5, @user.estimate_credits_to(:mb_op, size_megabytes: 5)
      assert_equal 5, @user.estimate_credits_to(:mb_op, size: 5.megabytes)

      # Test fractional values with different rounding strategies
      original_strategy = UsageCredits.configuration.rounding_strategy

      UsageCredits.configuration.rounding_strategy = :ceil
      assert_equal 6, @user.estimate_credits_to(:mb_op, mb: 5.1)

      UsageCredits.configuration.rounding_strategy = :floor
      assert_equal 5, @user.estimate_credits_to(:mb_op, mb: 5.1)

      UsageCredits.configuration.rounding_strategy = :round
      assert_equal 5, @user.estimate_credits_to(:mb_op, mb: 5.1)
      assert_equal 6, @user.estimate_credits_to(:mb_op, mb: 5.6)

      UsageCredits.configuration.rounding_strategy = original_strategy
    end

    # test "raises error for unknown units" do
    #   assert_raises(ArgumentError) do
    #     UsageCredits.configure do |config|
    #       operation :invalid_op do
    #         cost 1.credits_per(:invalid_unit)
    #       end
    #     end
    #   end
    # end

    test "compound operations use configured rounding strategy" do
      original_strategy = UsageCredits.configuration.rounding_strategy

      UsageCredits.configure do |config|
        operation :compound_op do
          cost 10.credits + 1.credits_per(:mb)
        end
        config.rounding_strategy = :ceil
      end

      # 10 base + 1.1 MB = 11.1 credits, should round up to 12
      assert_equal 12, @user.estimate_credits_to(:compound_op, mb: 1.1)

      UsageCredits.configuration.rounding_strategy = :floor
      # 10 base + 1.1 MB = 11.1 credits, should round down to 11
      assert_equal 11, @user.estimate_credits_to(:compound_op, mb: 1.1)

      # Reset configuration
      UsageCredits.configuration.rounding_strategy = original_strategy
    end

    ########################
    # Cost Classes #
    ########################

    test "fixed cost validates amount" do
      assert_raises(ArgumentError, "Credit amount must be a whole number (got: 1.5)") do
        UsageCredits::Cost::Fixed.new(1.5)
      end

      assert_raises(ArgumentError, "Credit amount cannot be negative (got: -1)") do
        UsageCredits::Cost::Fixed.new(-1)
      end

      # Valid amounts should work
      assert_nothing_raised do
        UsageCredits::Cost::Fixed.new(1)
      end
    end

    test "variable cost validates amount" do
      assert_raises(ArgumentError, "Credit amount must be a whole number (got: 1.5)") do
        UsageCredits::Cost::Variable.new(1.5, :mb)
      end

      assert_raises(ArgumentError, "Credit amount cannot be negative (got: -1)") do
        UsageCredits::Cost::Variable.new(-1, :mb)
      end

      # Valid amounts should work
      assert_nothing_raised do
        UsageCredits::Cost::Variable.new(1, :mb)
      end
    end

    test "compound cost addition works correctly" do
      UsageCredits.configure do |config|
        operation :compound_op do
          cost 10.credits + 1.credits_per(:mb) + 2.credits_per(:units)
        end
      end

      # Test that costs are summed correctly
      # 10 base + (1 credit * 5 MB) + (2 credits * 3 units) = 10 + 5 + 6 = 21
      assert_equal 21, @user.estimate_credits_to(:compound_op, mb: 5, units: 3)
    end

    test "compound cost uses configured rounding strategy" do
      original_strategy = UsageCredits.configuration.rounding_strategy

      UsageCredits.configure do |config|
        operation :compound_op do
          cost 10.credits + 1.credits_per(:mb) + 2.credits_per(:units)
        end
      end

      # Test with different rounding strategies
      # 10 base + (1 credit * 1.6 MB) + (2 credits * 1.7 units)
      # = 10 + 1.6 + 3.4 = 15 (round)
      UsageCredits.configuration.rounding_strategy = :round
      assert_equal 15, @user.estimate_credits_to(:compound_op, mb: 1.6, units: 1.7)

      # Same calculation but floor = 14
      UsageCredits.configuration.rounding_strategy = :floor
      assert_equal 14, @user.estimate_credits_to(:compound_op, mb: 1.6, units: 1.7)

      # Same calculation but ceil = 16
      UsageCredits.configuration.rounding_strategy = :ceil
      assert_equal 16, @user.estimate_credits_to(:compound_op, mb: 1.6, units: 1.7)

      # Reset configuration
      UsageCredits.configuration.rounding_strategy = original_strategy
    end

    test "compound cost handles proc costs" do
      UsageCredits.configure do |config|
        operation :dynamic_op do
          cost ->(params) { params[:base_cost].to_i }.credits + 1.credits_per(:mb)
        end
      end

      assert_equal 15, @user.estimate_credits_to(:dynamic_op, base_cost: 10, mb: 5)
    end

    test "compound cost validates proc results" do
      UsageCredits.configure do |config|
        operation :invalid_op do
          cost ->(params) { 1.5 }.credits
        end
      end

      assert_raises(InvalidOperation, "Error estimating cost: Credit amount must be a whole number (got: 1.5)") do
        @user.estimate_credits_to(:invalid_op)
      end
    end
  end
end
