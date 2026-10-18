# frozen_string_literal: true

require "test_helper"

# What leaving a transaction block with `return`, `break` or `throw` does on
# the Rails versions usage_credits supports (>= 7.2.3.1): the transaction
# commits. Rails 7.0 rolled back such a block, without an exception, when the
# block had written in its own transaction, and 7.1 did too unless
# `commit_transaction_on_non_local_return` was set; 7.2 commits it, and rolls
# back only when the block raised or its thread is being killed.
#
# Each block writes a row in its own transaction (the shape that 7.0 rolled
# back) and runs a wallet command, which writes in a savepoint of its own.
# Real transactions, not the fixture transaction, so the COMMIT or ROLLBACK
# reaches the database. The gem's own blocks leave with `next`; the exits
# here are deliberate.
class UsageCredits::TransactionExitTest < ActiveSupport::TestCase
  self.use_transactional_tests = false

  setup do
    @owner = User.create!(email: "transaction-exit-#{SecureRandom.hex(6)}@example.com", name: "Before")
    @wallet = @owner.credit_wallet
  end

  teardown do
    @owner.reload.destroy!
  end

  test "return out of a transaction block commits what the block wrote" do
    assert_equal :returned, write_and_return_from_transaction
    assert_committed name: "Returned from a transaction", balance: 10
  end

  test "return out of a with_lock block commits what the block wrote" do
    assert_equal :returned, write_and_return_from_lock
    assert_committed name: "Returned from a lock", balance: 10
  end

  test "break and throw out of a transaction block commit what the block wrote" do
    UsageCredits::Wallet.transaction do
      @owner.update!(name: "Broke out")
      @wallet.give_credits(10, reason: "break")
      break
    end
    assert_committed name: "Broke out", balance: 10

    catch(:done) do
      UsageCredits::Wallet.transaction do
        @owner.update!(name: "Thrown out")
        @wallet.give_credits(5, reason: "throw")
        throw :done
      end
    end
    assert_committed name: "Thrown out", balance: 15
  end

  private

  def write_and_return_from_transaction
    UsageCredits::Wallet.transaction do
      @owner.update!(name: "Returned from a transaction")
      @wallet.give_credits(10, reason: "return")
      return :returned
    end
    :fell_through
  end

  # The shape of every wallet command: its own transaction under the row lock.
  def write_and_return_from_lock
    @wallet.with_lock(requires_new: true) do
      @owner.update!(name: "Returned from a lock")
      @wallet.give_credits(10, reason: "return")
      return :returned
    end
    :fell_through
  end

  def assert_committed(name:, balance:)
    assert_equal 0, UsageCredits::Wallet.connection.open_transactions, "no transaction is left open to commit later"

    assert_equal name, User.find(@owner.id).name, "the block's own write was committed"
    wallet = UsageCredits::Wallet.find(@wallet.id)
    assert_equal balance, wallet.credits, "the wallet command's ledger rows were committed"
    assert_equal balance, wallet.read_attribute(:balance), "the cached balance was committed"
  end
end
