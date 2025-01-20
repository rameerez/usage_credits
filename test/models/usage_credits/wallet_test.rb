# test/models/usage_credits/wallet_test.rb
require "test_helper"

class UsageCredits::WalletTest < ActiveSupport::TestCase
  setup do
    @user = users(:default)
    @wallet = @user.credit_wallet
  end

  test "user has a wallet" do
    assert_not_nil @wallet
    assert_instance_of UsageCredits::Wallet, @wallet
  end

  test "wallet starts with zero balance" do
    assert_equal 0, @user.credits
  end

  test "can give credits" do
    @user.give_credits(100, reason: "signup")
    assert_equal 100, @user.credits
  end

  test "can spend credits" do
    @user.give_credits(100, reason: "signup")
    @user.spend_credits_on(:test_operation)
    assert_equal 99, @user.credits  # Assuming test_operation costs 1 credit
  end

  test "cannot spend more credits than available" do
    @user.give_credits(1, reason: "signup")
    assert_raises(UsageCredits::InsufficientCredits) do
      @user.spend_credits_on(:expensive_operation)  # Assuming this costs more than 1 credit
    end
    assert_equal 1, @user.credits # Balance should remain unchanged
  end

  test "tracks credit history" do
    @user.give_credits(100, reason: "signup")
    @user.spend_credits_on(:test_operation)

    assert_equal 2, @user.credit_history.count
    assert_equal ["signup_bonus", "operation_charge"], @user.credit_history.pluck(:category)
    assert_equal [100, -1], @user.credit_history.pluck(:amount)
  end
end
