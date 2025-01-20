# frozen_string_literal: true

require "test_helper"

module UsageCredits
  class CreditSystemTest < ActiveSupport::TestCase
    setup do
      @user = users(:default)
      @wallet = @user.credit_wallet
    end

    #####################
    # Core Wallet Tests #
    #####################

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
      assert_equal "test_operation", charge.metadata["operation"]
      assert_equal 1, charge.metadata["cost"]
      assert_not_nil charge.metadata["executed_at"]
    end

    test "can filter history by category" do
      @user.give_credits(100, reason: "signup")
      @user.spend_credits_on(:test_operation)

      assert_equal 1, @user.credit_history.by_category(:signup_bonus).count
      assert_equal 1, @user.credit_history.by_category(:operation_charge).count
    end
  end
end
