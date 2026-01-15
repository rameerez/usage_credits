# frozen_string_literal: true

require "test_helper"

class WalletCallbacksIntegrationTest < ActiveSupport::TestCase
  setup do
    @user = users(:rich_user)
    # Clear any existing transactions to start fresh
    @user.credit_wallet.transactions.destroy_all
  end

  test "add_credits triggers credits_added callback with transaction" do
    events = []
    UsageCredits.configure do |config|
      config.on_credits_added { |ctx| events << ctx }
    end

    transaction = @user.credit_wallet.add_credits(500, category: :manual_adjustment)

    assert_equal 1, events.size
    ctx = events.first
    assert_equal :credits_added, ctx.event
    assert_equal 500, ctx.amount
    assert_equal :manual_adjustment, ctx.category
    assert_equal transaction, ctx.transaction
    assert_equal @user.credit_wallet, ctx.wallet
    assert_equal @user, ctx.owner
    assert_equal 0, ctx.previous_balance
    assert_equal 500, ctx.new_balance
  end

  test "deduct_credits triggers credits_deducted callback" do
    events = []
    UsageCredits.configure do |config|
      config.on_credits_deducted { |ctx| events << ctx }
    end

    @user.credit_wallet.add_credits(200)
    @user.credit_wallet.deduct_credits(50)

    assert_equal 1, events.size
    ctx = events.first
    assert_equal :credits_deducted, ctx.event
    assert_equal 50, ctx.amount
    assert_equal 200, ctx.previous_balance
    assert_equal 150, ctx.new_balance
  end

  test "deduct_credits triggers low_balance_reached when crossing threshold" do
    events = []
    UsageCredits.configure do |config|
      config.low_balance_threshold = 100
      config.on_low_balance_reached { |ctx| events << ctx }
    end

    @user.credit_wallet.add_credits(150)
    @user.credit_wallet.deduct_credits(100)

    assert_equal 1, events.size
    ctx = events.first
    assert_equal :low_balance_reached, ctx.event
    assert_equal 100, ctx.threshold
    assert_equal 150, ctx.previous_balance
    assert_equal 50, ctx.new_balance
  end

  test "low_balance_reached only fires when crossing threshold, not when already below" do
    events = []
    UsageCredits.configure do |config|
      config.low_balance_threshold = 100
      config.on_low_balance_reached { |ctx| events << ctx }
    end

    # Start with balance below threshold
    @user.credit_wallet.add_credits(50)
    events.clear  # Clear the credits_added event if any

    # Deduct while already below threshold - should NOT fire
    @user.credit_wallet.deduct_credits(10)

    assert_equal 0, events.size
  end

  test "deduct_credits triggers balance_depleted when reaching zero" do
    events = []
    UsageCredits.configure do |config|
      config.on_balance_depleted { |ctx| events << ctx }
    end

    @user.credit_wallet.add_credits(50)
    @user.credit_wallet.deduct_credits(50)

    assert_equal 1, events.size
    ctx = events.first
    assert_equal :balance_depleted, ctx.event
    assert_equal 50, ctx.previous_balance
    assert_equal 0, ctx.new_balance
  end

  test "balance_depleted does not fire when balance stays above zero" do
    events = []
    UsageCredits.configure do |config|
      config.on_balance_depleted { |ctx| events << ctx }
    end

    @user.credit_wallet.add_credits(100)
    @user.credit_wallet.deduct_credits(50)

    assert_equal 0, events.size
  end

  test "spend_credits_on triggers insufficient_credits before raising" do
    events = []
    UsageCredits.configure do |config|
      config.on_insufficient_credits { |ctx| events << ctx }
      config.operation(:expensive_op) { costs 1000.credits }
    end

    @user.credit_wallet.add_credits(10)

    assert_raises(UsageCredits::InsufficientCredits) do
      @user.credit_wallet.spend_credits_on(:expensive_op)
    end

    assert_equal 1, events.size
    ctx = events.first
    assert_equal :insufficient_credits, ctx.event
    assert_equal 1000, ctx.amount
    assert_equal :expensive_op, ctx.operation_name
    assert_equal 10, ctx.metadata[:available]
  end

  test "multiple callbacks can be configured for different events" do
    added_events = []
    deducted_events = []

    UsageCredits.configure do |config|
      config.on_credits_added { |ctx| added_events << ctx }
      config.on_credits_deducted { |ctx| deducted_events << ctx }
    end

    @user.credit_wallet.add_credits(100)
    @user.credit_wallet.deduct_credits(30)

    assert_equal 1, added_events.size
    assert_equal 1, deducted_events.size
    assert_equal :credits_added, added_events.first.event
    assert_equal :credits_deducted, deducted_events.first.event
  end

  test "callback errors do not break credit operations" do
    UsageCredits.configure do |config|
      config.on_credits_added { |_| raise "Callback error!" }
    end

    # Should not raise - callback error is isolated
    transaction = @user.credit_wallet.add_credits(100)

    assert_not_nil transaction
    assert_equal 100, @user.credit_wallet.credits
  end
end
