# frozen_string_literal: true

require "test_helper"

# A refused spend_credits_on whose block had already spent on the same wallet
# instance must leave that instance usable: the next command on it runs.
# Rails restores a rolled-back record's attributes to the values it had
# written, marked as unsaved changes, and refuses to lock a record with
# unsaved changes; wallets 0.4.2 discards the ledger's own columns before the
# lock. Real transactions, not the fixture transaction: inside a savepoint
# Rails does not restore the rolled-back values, so the trap only springs
# where production runs.
class UsageCredits::RolledBackCommandTest < ActiveSupport::TestCase
  self.use_transactional_tests = false

  setup do
    UsageCredits.configure { |config| config.operation(:ten_credit_task) { costs 10.credits } }
    @owner = User.create!(email: "rolled-back-#{SecureRandom.hex(6)}@example.com", name: "Rolled Back")
    @wallet = @owner.credit_wallet
    @wallet.give_credits(100, reason: "signup")
  end

  teardown do
    @owner.reload.destroy!
  end

  test "the wallet instance stays usable after spend_credits_on is refused because its block spent the credits" do
    wallet = @wallet
    error = assert_raises(UsageCredits::InsufficientCredits) do
      wallet.spend_credits_on(:ten_credit_task) { wallet.deduct_credits(95) }
    end
    assert_equal "Insufficient credits (5 < 10)", error.message
    assert_equal 100, wallet.credits, "the block's spending rolled back with the refusal"

    spend = wallet.spend_credits_on(:ten_credit_task) {}
    assert_equal(-10, spend.amount)
    assert_equal 90, wallet.reload.credits
    assert_equal 90, wallet.read_attribute(:balance), "the cached balance matches the ledger"
  end

  test "the wallet instance stays usable after the caller's transaction rolled a command back" do
    wallet = @wallet
    assert_raises(RuntimeError) do
      UsageCredits::Wallet.transaction do
        wallet.deduct_credits(10)
        raise "the caller's own failure"
      end
    end

    wallet.give_credits(5, reason: "promo")
    assert_equal 105, wallet.reload.credits
  end
end
