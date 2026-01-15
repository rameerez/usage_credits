# frozen_string_literal: true

require "test_helper"

class UsageCredits::CallbacksTest < ActiveSupport::TestCase
  setup do
    @user = users(:rich_user)
    @user.credit_wallet  # Ensure wallet exists
  end

  test "dispatch calls configured callback with context" do
    called_with = nil
    UsageCredits.configure do |config|
      config.on_credits_added { |ctx| called_with = ctx }
    end

    wallet = @user.credit_wallet
    UsageCredits::Callbacks.dispatch(:credits_added, wallet: wallet, amount: 100, new_balance: 100)

    assert_not_nil called_with
    assert_equal :credits_added, called_with.event
    assert_equal 100, called_with.amount
    assert_equal wallet, called_with.wallet
  end

  test "dispatch isolates callback errors and does not raise" do
    UsageCredits.configure do |config|
      config.on_credits_added { |_| raise "Boom!" }
    end

    assert_nothing_raised do
      UsageCredits::Callbacks.dispatch(:credits_added, wallet: @user.credit_wallet, amount: 100)
    end
  end

  test "dispatch handles callbacks with zero arity" do
    called = false
    UsageCredits.configure do |config|
      config.on_credits_added { called = true }
    end

    UsageCredits::Callbacks.dispatch(:credits_added, wallet: @user.credit_wallet, amount: 100)

    assert called
  end

  test "dispatch does nothing when no callback configured" do
    # No callback set - should not raise
    assert_nothing_raised do
      UsageCredits::Callbacks.dispatch(:credits_added, wallet: @user.credit_wallet, amount: 100)
    end
  end

  test "CallbackContext provides owner convenience method" do
    wallet = @user.credit_wallet
    ctx = UsageCredits::CallbackContext.new(event: :test, wallet: wallet)

    assert_equal wallet.owner, ctx.owner
  end

  test "CallbackContext to_h returns compact hash without nil values" do
    ctx = UsageCredits::CallbackContext.new(
      event: :test,
      wallet: @user.credit_wallet,
      amount: 100,
      previous_balance: nil
    )

    hash = ctx.to_h
    assert_equal :test, hash[:event]
    assert_equal 100, hash[:amount]
    assert_not hash.key?(:previous_balance)  # nil values should be excluded
  end

  test "calling DSL method without block clears the callback" do
    UsageCredits.configure do |config|
      config.on_credits_added { |_| "initial" }
    end

    assert_not_nil UsageCredits.configuration.on_credits_added_callback

    # Clear by calling without block
    UsageCredits.configure do |config|
      config.on_credits_added  # No block = clears
    end

    assert_nil UsageCredits.configuration.on_credits_added_callback
  end

  test "dispatch handles all 7 callback events" do
    events_received = []

    UsageCredits.configure do |config|
      config.on_credits_added { |ctx| events_received << ctx.event }
      config.on_credits_deducted { |ctx| events_received << ctx.event }
      config.on_low_balance_reached { |ctx| events_received << ctx.event }
      config.on_balance_depleted { |ctx| events_received << ctx.event }
      config.on_insufficient_credits { |ctx| events_received << ctx.event }
      config.on_subscription_credits_awarded { |ctx| events_received << ctx.event }
      config.on_credit_pack_purchased { |ctx| events_received << ctx.event }
    end

    wallet = @user.credit_wallet

    UsageCredits::Callbacks.dispatch(:credits_added, wallet: wallet, amount: 100)
    UsageCredits::Callbacks.dispatch(:credits_deducted, wallet: wallet, amount: 50)
    UsageCredits::Callbacks.dispatch(:low_balance_reached, wallet: wallet, threshold: 10)
    UsageCredits::Callbacks.dispatch(:balance_depleted, wallet: wallet, previous_balance: 10)
    UsageCredits::Callbacks.dispatch(:insufficient_credits, wallet: wallet, amount: 1000)
    UsageCredits::Callbacks.dispatch(:subscription_credits_awarded, wallet: wallet, amount: 500)
    UsageCredits::Callbacks.dispatch(:credit_pack_purchased, wallet: wallet, amount: 200)

    assert_equal 7, events_received.size
    assert_includes events_received, :credits_added
    assert_includes events_received, :credits_deducted
    assert_includes events_received, :low_balance_reached
    assert_includes events_received, :balance_depleted
    assert_includes events_received, :insufficient_credits
    assert_includes events_received, :subscription_credits_awarded
    assert_includes events_received, :credit_pack_purchased
  end
end
