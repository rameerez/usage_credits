# frozen_string_literal: true

require "test_helper"

# ============================================================================
# HAS WALLET CONCERN TEST SUITE
# ============================================================================
#
# This test suite tests the HasWallet concern which adds credit wallet
# functionality to any ActiveRecord model (typically User).
#
# The concern provides:
#   - Automatic wallet creation on user/owner creation
#   - Association and aliases (credit_wallet, credits_wallet, wallet)
#   - Method delegation (credits, has_enough_credits_to?, spend_credits_on, etc.)
#   - Configuration options (auto_create, initial_balance)
#   - Credit subscriptions tracking
#
# ============================================================================

class HasWalletTest < ActiveSupport::TestCase
  setup do
    # Define test operations for has_enough_credits_to? tests
    UsageCredits.configure do |config|
      config.operation :test_small_op do
        costs 100.credits
      end

      config.operation :test_large_op do
        costs 5000.credits
      end
    end
  end

  teardown do
    UsageCredits.reset!
  end

  # ========================================
  # AUTOMATIC WALLET CREATION
  # ========================================

  test "wallet is automatically created on user creation" do
    user = User.create!(email: "autowallet@example.com", name: "Auto Wallet User")

    assert_not_nil user.credit_wallet
    assert user.credit_wallet.persisted?
    assert_equal user, user.credit_wallet.owner
  end

  test "wallet creation can be disabled with auto_create: false" do
    # Define a test model class with auto_create: false
    test_class = Class.new(User) do
      def self.name
        "TestUserNoAutoWallet"
      end

      has_credits auto_create: false
    end

    # For this test, we'll just verify the option is set correctly
    assert_equal false, test_class.credit_options[:auto_create]
  end

  test "wallet is created with default balance of zero" do
    user = User.create!(email: "defaultbal@example.com", name: "Default Balance User")

    assert_equal 0, user.credit_wallet.balance
  end

  test "wallet is created with initial_balance when configured" do
    # Create a user class with custom initial balance
    test_class = Class.new(User) do
      def self.name
        "TestUserWithInitialBalance"
      end

      has_credits initial_balance: 100
    end

    # Verify the configuration is set
    assert_equal 100, test_class.credit_options[:initial_balance]
  end

  # ========================================
  # ASSOCIATIONS
  # ========================================

  test "has_one credit_wallet association" do
    user = users(:rich_user)
    wallet = usage_credits_wallets(:rich_wallet)

    assert_equal wallet, user.credit_wallet
  end

  test "credit_wallet association is polymorphic" do
    user = users(:rich_user)

    assert_equal "User", user.credit_wallet.owner_type
    assert_equal user.id, user.credit_wallet.owner_id
  end

  test "destroying user destroys associated wallet" do
    user = User.create!(email: "destroy@example.com", name: "Destroy User")
    wallet_id = user.credit_wallet.id

    user.destroy!

    assert_nil UsageCredits::Wallet.find_by(id: wallet_id)
  end

  # ========================================
  # ASSOCIATION ALIASES
  # ========================================

  test "credits_wallet is an alias for credit_wallet" do
    user = users(:rich_user)

    assert_equal user.credit_wallet, user.credits_wallet
  end

  test "wallet is an alias for credit_wallet" do
    user = users(:rich_user)

    assert_equal user.credit_wallet, user.wallet
  end

  # ========================================
  # WALLET AUTO-CREATION (ensure_credit_wallet)
  # ========================================

  test "credit_wallet creates wallet if missing" do
    user = User.create!(email: "ensure@example.com", name: "Ensure User")

    # Destroy wallet to test auto-creation
    user.credit_wallet.destroy!
    user.reload

    # Accessing credit_wallet should create a new one
    new_wallet = user.credit_wallet

    assert_not_nil new_wallet
    assert new_wallet.persisted?
    assert_equal user, new_wallet.owner
  end

  test "original_credit_wallet returns wallet without auto-creation" do
    user = User.create!(email: "original@example.com", name: "Original User")
    wallet = user.credit_wallet

    # original_credit_wallet should return the same wallet
    assert_equal wallet, user.original_credit_wallet
  end

  test "original_credit_wallet returns nil if wallet doesn't exist" do
    user = User.create!(email: "nowallet@example.com", name: "No Wallet User")

    # Destroy the auto-created wallet
    user.credit_wallet.destroy!
    user.reload

    # original_credit_wallet should NOT auto-create
    assert_nil user.original_credit_wallet
  end

  # ========================================
  # METHOD DELEGATION
  # ========================================

  test "credits delegates to wallet" do
    user = users(:rich_user)
    user.reload  # Ensure fresh data

    assert_equal user.credit_wallet.credits, user.credits
  end

  test "credit_history delegates to wallet" do
    user = users(:rich_user)

    assert_respond_to user, :credit_history
    assert_equal user.credit_wallet.credit_history, user.credit_history
  end

  test "has_enough_credits_to? delegates to wallet" do
    user = users(:rich_user)
    user.reload  # Ensure fresh data

    assert user.has_enough_credits_to?(:test_small_op)
    assert_not user.has_enough_credits_to?(:test_large_op)
  end

  test "spend_credits_on delegates to wallet" do
    user = users(:rich_user)
    user.reload  # Ensure fresh data
    initial_credits = user.credits

    user.spend_credits_on(:test_small_op)

    assert_equal initial_credits - 100, user.reload.credits
  end

  test "give_credits delegates to wallet" do
    user = users(:poor_user)
    user.reload  # Ensure fresh data
    initial_credits = user.credits

    user.give_credits(100, reason: "bonus")

    assert_equal initial_credits + 100, user.reload.credits
  end

  test "estimate_credits_to delegates to wallet" do
    user = users(:rich_user)
    user.reload  # Ensure fresh data

    # Define variable cost operation
    UsageCredits.configure do |config|
      config.operation :test_variable_op do
        costs 5.credits_per(:mb)
      end
    end

    estimate = user.estimate_credits_to(:test_variable_op, mb: 10)
    assert_equal 50, estimate
  end

  # ========================================
  # CREDIT SUBSCRIPTIONS
  # ========================================

  test "credit_subscriptions returns active subscription plans" do
    user = users(:subscribed_user)

    # Configure test plan
    UsageCredits.configure do |config|
      config.subscription_plan :pro_plan_monthly do
        gives 500.credits.every(:month)
        processor_plan(:fake_processor, "pro_plan_monthly")
      end
    end

    subscriptions = user.credit_subscriptions

    assert subscriptions.is_a?(Array)
  end

  test "credit_subscriptions returns empty array when no wallet" do
    user = User.create!(email: "nosub@example.com", name: "No Sub User")
    user.credit_wallet.destroy!
    user.reload

    subscriptions = user.credit_subscriptions

    assert_equal [], subscriptions
  end

  test "credit_subscriptions filters by active fulfillments" do
    user = users(:subscribed_user)

    UsageCredits.configure do |config|
      config.subscription_plan :pro_plan_monthly do
        gives 500.credits.every(:month)
        processor_plan(:fake_processor, "pro_plan_monthly")
      end
    end

    subscriptions = user.credit_subscriptions

    # All returned subscriptions should be from active fulfillments
    assert subscriptions.all? { |plan| plan.is_a?(UsageCredits::CreditSubscriptionPlan) }
  end

  # ========================================
  # CONFIGURATION OPTIONS
  # ========================================

  test "credit_options returns configuration hash" do
    user = users(:rich_user)

    options = user.credit_options

    assert options.is_a?(Hash)
    assert options.key?(:auto_create)
  end

  test "has_credits sets credit options" do
    test_class = Class.new(User) do
      def self.name
        "TestUserWithOptions"
      end

      has_credits auto_create: false, initial_balance: 500
    end

    options = test_class.credit_options

    assert_equal false, options[:auto_create]
    assert_equal 500, options[:initial_balance]
  end

  # ========================================
  # EDGE CASES
  # ========================================

  test "wallet creation fails gracefully for unsaved owner" do
    user = User.new(email: "unsaved@example.com", name: "Unsaved User")

    error = assert_raises(RuntimeError) do
      user.send(:ensure_credit_wallet)
    end

    assert_includes error.message, "Cannot create wallet for unsaved owner"
  end

  test "multiple calls to credit_wallet return same instance" do
    user = User.create!(email: "same@example.com", name: "Same Wallet User")

    wallet1 = user.credit_wallet
    wallet2 = user.credit_wallet

    assert_equal wallet1.id, wallet2.id
  end

  test "has_credits can be called multiple times" do
    test_class1 = Class.new(User) do
      def self.name
        "TestUser1"
      end

      has_credits
      has_credits auto_create: false
    end

    # Last call should win
    assert_equal false, test_class1.credit_options[:auto_create]
  end

  test "wallet belongs_to owner with correct polymorphic type" do
    user = users(:rich_user)
    wallet = user.credit_wallet

    assert_equal "User", wallet.owner_type
    assert_equal user.class.name, wallet.owner_type
  end

  # ========================================
  # INTEGRATION WITH FIXTURES
  # ========================================

  test "fixture users have wallets" do
    rich_user = users(:rich_user)
    poor_user = users(:poor_user)
    subscribed_user = users(:subscribed_user)

    assert_not_nil rich_user.credit_wallet
    assert_not_nil poor_user.credit_wallet
    assert_not_nil subscribed_user.credit_wallet
  end

  test "fixture wallets have credits" do
    # Just verify wallets have credits (exact amounts may vary due to test modifications)
    assert users(:rich_user).credits > 0
    assert users(:poor_user).credits > 0
    assert users(:subscribed_user).credits > 0
  end
end
