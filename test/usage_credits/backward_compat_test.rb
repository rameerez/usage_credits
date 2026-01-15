# frozen_string_literal: true

require "test_helper"

class BackwardCompatibilityTest < ActiveSupport::TestCase
  setup do
    @user = users(:rich_user)
    @user.credit_wallet.transactions.destroy_all
  end

  test "on_low_balance legacy callback receives owner not context" do
    received_arg = nil
    UsageCredits.configure do |config|
      config.low_balance_threshold = 100
      config.on_low_balance { |owner| received_arg = owner }
    end

    @user.credit_wallet.add_credits(150)
    @user.credit_wallet.deduct_credits(100)

    # Legacy callback should receive owner directly
    assert_equal @user, received_arg
    assert_kind_of User, received_arg  # NOT a CallbackContext
  end

  test "on_low_balance_reached new callback receives context" do
    received_arg = nil
    UsageCredits.configure do |config|
      config.low_balance_threshold = 100
      config.on_low_balance_reached { |ctx| received_arg = ctx }
    end

    @user.credit_wallet.add_credits(150)
    @user.credit_wallet.deduct_credits(100)

    # New callback should receive CallbackContext
    assert_kind_of UsageCredits::CallbackContext, received_arg
    assert_equal @user, received_arg.owner
    assert_equal :low_balance_reached, received_arg.event
    assert_equal 100, received_arg.threshold
  end

  test "on_low_balance sets both legacy callback and new callback wrapper" do
    UsageCredits.configure do |config|
      config.low_balance_threshold = 100
      config.on_low_balance { |owner| "legacy callback with #{owner}" }
    end

    # Both should be set
    assert_not_nil UsageCredits.configuration.low_balance_callback
    assert_not_nil UsageCredits.configuration.on_low_balance_reached_callback
  end

  test "deprecated handle_event still works but logs deprecation" do
    received_owner = nil
    UsageCredits.configure do |config|
      config.on_low_balance { |owner| received_owner = owner }
    end

    # This should work but log deprecation (captured by warn)
    _output = capture_io do
      UsageCredits.handle_event(:low_balance_reached, wallet: @user.credit_wallet)
    end

    # The callback should still be called
    assert_equal @user, received_owner
  end

  test "deprecated notify_low_balance still works" do
    received_owner = nil
    UsageCredits.configure do |config|
      config.on_low_balance { |owner| received_owner = owner }
    end

    _output = capture_io do
      UsageCredits.notify_low_balance(@user)
    end

    assert_equal @user, received_owner
  end

  test "deprecation warnings only fire once per method" do
    UsageCredits.configure do |config|
      config.on_low_balance { |_| }
    end

    # Call multiple times
    first_output = capture_io { UsageCredits.handle_event(:low_balance_reached, wallet: @user.credit_wallet) }
    second_output = capture_io { UsageCredits.handle_event(:low_balance_reached, wallet: @user.credit_wallet) }

    # First call should have deprecation warning
    assert_match /DEPRECATION/, first_output[1]

    # Second call should NOT have warning (already warned)
    refute_match /DEPRECATION/, second_output[1]
  end

  test "reset! clears deprecation warnings" do
    UsageCredits.configure do |config|
      config.on_low_balance { |_| }
    end

    # First call - should warn
    first_output = capture_io { UsageCredits.handle_event(:low_balance_reached, wallet: @user.credit_wallet) }
    assert_match /DEPRECATION/, first_output[1]

    # Reset
    UsageCredits.reset!

    # Reconfigure after reset
    UsageCredits.configure do |config|
      config.on_low_balance { |_| }
    end

    # Should warn again after reset
    after_reset_output = capture_io { UsageCredits.handle_event(:low_balance_reached, wallet: @user.credit_wallet) }
    assert_match /DEPRECATION/, after_reset_output[1]
  end
end
