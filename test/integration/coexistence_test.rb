# frozen_string_literal: true

require "test_helper"

# This test verifies that the wallets gem and usage_credits gem can coexist
# in the same Rails application without conflicts.
#
# Plan requirements tested:
# - One model uses direct has_wallets (Team)
# - One model uses has_credits (User)
# - Direct wallets write to wallets_* tables
# - Usage credits write to usage_credits_* tables
# - Cross-transfer between gems is rejected
class CoexistenceTest < ActiveSupport::TestCase
  # Load both wallets gem fixtures and usage_credits fixtures
  fixtures :teams, :users

  setup do
    # Ensure clean state for wallets gem tables
    Wallets::Wallet.where(owner_type: "Team").delete_all
  end

  test "Team model uses has_wallets from wallets gem" do
    team = teams(:alpha_team)

    # Should be able to create a wallet via the wallets gem
    wallet = team.wallet(:points)

    assert_instance_of Wallets::Wallet, wallet
    assert_equal "points", wallet.asset_code
    assert_equal "Team", wallet.owner_type
    assert_equal team.id, wallet.owner_id
  end

  test "User model uses has_credits from usage_credits gem" do
    user = users(:rich_user)
    wallet = user.credit_wallet

    assert_instance_of UsageCredits::Wallet, wallet
    assert_equal "credits", wallet.asset_code
    assert_equal "User", wallet.owner_type
    assert_equal user.id, wallet.owner_id
  end

  test "wallets gem writes to wallets_wallets table" do
    team = teams(:alpha_team)
    team.wallet(:points).credit(100, category: :reward)

    # Verify data is in wallets_wallets table
    wallet_record = Wallets::Wallet.find_by(owner_type: "Team", owner_id: team.id, asset_code: "points")
    assert_not_nil wallet_record
    assert_equal 100, wallet_record.balance

    # Verify NOT in usage_credits_wallets table
    uc_record = UsageCredits::Wallet.find_by(owner_type: "Team", owner_id: team.id)
    assert_nil uc_record
  end

  test "usage_credits gem writes to usage_credits_wallets table" do
    user = User.create!(email: "coexist-#{SecureRandom.hex(4)}@example.com", name: "Coexist User")
    user.give_credits(100, reason: "test")

    # Verify data is in usage_credits_wallets table
    uc_record = UsageCredits::Wallet.find_by(owner_type: "User", owner_id: user.id, asset_code: "credits")
    assert_not_nil uc_record
    assert_equal 100, uc_record.balance

    # Verify NOT in wallets_wallets table
    wallet_record = Wallets::Wallet.find_by(owner_type: "User", owner_id: user.id)
    assert_nil wallet_record
  end

  test "wallets gem transfers stay within wallets_* tables" do
    team1 = teams(:alpha_team)
    team2 = teams(:beta_team)

    team1.wallet(:points).credit(100, category: :reward)
    team2.wallet(:points)  # Ensure wallet exists

    transfer = team1.wallet(:points).transfer_to(team2.wallet(:points), 30, category: :gift)

    # Verify transfer is in wallets_transfers table
    assert_instance_of Wallets::Transfer, transfer
    assert_equal 30, transfer.amount
    assert_equal 70, team1.wallet(:points).reload.balance
    assert_equal 30, team2.wallet(:points).reload.balance

    # Verify no records in usage_credits_transfers
    assert_equal 0, UsageCredits::Transfer.where(from_wallet_id: team1.wallet(:points).id).count
  end

  test "usage_credits gem transfers stay within usage_credits_* tables" do
    user1 = User.create!(email: "sender-coex-#{SecureRandom.hex(4)}@example.com", name: "Sender")
    user2 = User.create!(email: "recipient-coex-#{SecureRandom.hex(4)}@example.com", name: "Recipient")

    user1.give_credits(100, reason: "test")

    transfer = nil

    assert_difference -> { UsageCredits::Transfer.count }, 1 do
      assert_difference -> { UsageCredits::Transaction.count }, 2 do
        assert_no_difference -> { Wallets::Transfer.count } do
          assert_no_difference -> { Wallets::Transaction.count } do
            transfer = user1.credit_wallet.transfer_to(user2.credit_wallet, 30, category: :gift)
          end
        end
      end
    end

    # Verify transfer is in usage_credits_transfers table
    assert_instance_of UsageCredits::Transfer, transfer
    assert_equal 30, transfer.amount
    assert_equal 70, user1.credits
    assert_equal 30, user2.credits
    assert_instance_of UsageCredits::Transaction, transfer.outbound_transaction
    assert_equal [UsageCredits::Transaction], transfer.inbound_transactions.map(&:class).uniq
    assert_equal 1, transfer.inbound_transactions.count
    assert_equal "preserve", transfer.expiration_policy
  end

  test "cross-gem transfers are rejected" do
    team = teams(:alpha_team)
    user = User.create!(email: "cross-#{SecureRandom.hex(4)}@example.com", name: "Cross User")

    # Use same asset code for both to test class mismatch specifically
    # (asset mismatch check happens before class check in transfer_to)
    team.wallet(:credits).credit(100, category: :reward)
    user.give_credits(100, reason: "test")

    # Attempting to transfer from wallets gem wallet to usage_credits gem wallet
    # should fail because the wallet classes are different
    error = assert_raises(Wallets::InvalidTransfer) do
      team.wallet(:credits).transfer_to(user.credit_wallet, 30, category: :gift)
    end
    assert_equal "Wallet classes must match", error.message

    # Reverse direction should also fail
    error = assert_raises(Wallets::InvalidTransfer) do
      user.credit_wallet.transfer_to(team.wallet(:credits), 30, category: :gift)
    end
    assert_equal "Wallet classes must match", error.message
  end

  test "transactions use correct classes and tables per gem" do
    team = teams(:alpha_team)
    user = User.create!(email: "tx-#{SecureRandom.hex(4)}@example.com", name: "TX User")

    team.wallet(:points).credit(100, category: :reward)
    user.give_credits(100, reason: "test")

    # Wallets gem transactions
    team_transactions = team.wallet(:points).transactions
    assert team_transactions.all? { |tx| tx.is_a?(Wallets::Transaction) }

    # Usage credits transactions
    user_transactions = user.credit_wallet.transactions
    assert user_transactions.all? { |tx| tx.is_a?(UsageCredits::Transaction) }
  end

  test "callbacks are isolated between gems" do
    wallets_callback_fired = false
    usage_credits_callback_fired = false

    # Set up wallets gem callback
    original_wallets_callback = Wallets.configuration.instance_variable_get(:@on_balance_credited_callback)
    Wallets.configure do |config|
      config.on_balance_credited { |_ctx| wallets_callback_fired = true }
    end

    # Set up usage_credits gem callback
    original_uc_callback = UsageCredits.configuration.instance_variable_get(:@on_credits_added_callback)
    UsageCredits.configure do |config|
      config.on_credits_added { |_ctx| usage_credits_callback_fired = true }
    end

    # Credit via wallets gem
    team = teams(:alpha_team)
    team.wallet(:points).credit(50, category: :reward)

    assert wallets_callback_fired, "Wallets gem callback should have fired"
    assert_not usage_credits_callback_fired, "Usage credits callback should NOT have fired for wallets gem operation"

    # Reset flags
    wallets_callback_fired = false
    usage_credits_callback_fired = false

    # Credit via usage_credits gem
    user = User.create!(email: "callback-#{SecureRandom.hex(4)}@example.com", name: "Callback User")
    user.give_credits(50, reason: "test")

    assert usage_credits_callback_fired, "Usage credits callback should have fired"
    assert_not wallets_callback_fired, "Wallets gem callback should NOT have fired for usage_credits operation"

    # Restore original callbacks
    Wallets.configuration.instance_variable_set(:@on_balance_credited_callback, original_wallets_callback)
    UsageCredits.configuration.instance_variable_set(:@on_credits_added_callback, original_uc_callback)
  end
end
