# frozen_string_literal: true

require "test_helper"

# ============================================================================
# PAY CHARGE EXTENSION TEST SUITE
# ============================================================================
#
# This test suite tests the PayChargeExtension concern that integrates the
# Pay gem with our UsageCredits system. The extension uses after_commit
# callbacks to automatically fulfill credit packs when charges succeed and
# handle refunds when charges are refunded.
#
# ## IMPORTANT: Fixture Wallet Usage
#
# When using fixture users (like `users(:new_user)`), always use
# `user.credit_wallet` to get the existing fixture wallet instead of creating
# a new wallet with `UsageCredits::Wallet.create!(owner: user)`.
#
# The fixtures already define wallets for users. Creating a new wallet would
# result in TWO wallets for the same owner. The after_commit callback looks up
# the wallet via `customer.owner.credit_wallet`, which returns the FIXTURE
# wallet, not the newly created one. This causes tests to fail because they
# check the wrong wallet.
#
# For tests that need a truly fresh user/wallet, use:
#   user = User.create!(email: "unique@example.com", name: "Test User")
#   wallet = user.credit_wallet  # Auto-created by HasWallet concern
#
# ============================================================================

class PayChargeExtensionTest < ActiveSupport::TestCase
  setup do
    # Configure test credit packs matching our fixtures
    UsageCredits.configure do |config|
      config.credit_pack :starter do
        gives 1000.credits
        costs 49.dollars
      end

      config.credit_pack :pro do
        gives 5000.credits
        costs 99.dollars
      end

      config.credit_pack :bonus_pack do
        gives 500.credits
        bonus 100.credits  # Total: 600 credits
        costs 29.dollars
      end
    end
  end

  # ========================================
  # HELPER METHODS
  # ========================================

  test "init_metadata initializes metadata and data hashes" do
    charge = Pay::Charge.new

    assert_not_nil charge.metadata
    assert_not_nil charge.data
    assert_kind_of Hash, charge.metadata
    assert_kind_of Hash, charge.data
  end

  test "succeeded? returns true for succeeded Stripe charge with status in data (legacy Pay)" do
    charge = pay_charges(:completed_charge)
    charge.type = "Pay::Stripe::Charge"

    assert charge.succeeded?
  end

  test "succeeded? returns true when status is in object column (Pay 10+)" do
    charge = Pay::Charge.new(
      type: "Pay::Stripe::Charge",
      amount: 4900,
      object: { "status" => "succeeded", "amount_captured" => 4900 },
      data: {}  # Empty data to simulate Pay 10+ behavior
    )

    assert charge.succeeded?
  end

  test "succeeded? returns false when status is failed in object column (Pay 10+)" do
    charge = Pay::Charge.new(
      type: "Pay::Stripe::Charge",
      amount: 4900,
      object: { "status" => "failed", "amount_captured" => 0 },
      data: {}
    )

    assert_not charge.succeeded?
  end

  test "succeeded? falls back to data column when object is empty (legacy Pay)" do
    charge = Pay::Charge.new(
      type: "Pay::Stripe::Charge",
      amount: 4900,
      object: {},  # Empty object
      data: { "status" => "succeeded", "amount_captured" => 4900 }
    )

    assert charge.succeeded?
  end

  test "succeeded? prefers object over data when both have values (Pay 10+)" do
    # In Pay 10+, object should be authoritative
    charge = Pay::Charge.new(
      type: "Pay::Stripe::Charge",
      amount: 4900,
      object: { "status" => "failed", "amount_captured" => 0 },
      data: { "status" => "succeeded", "amount_captured" => 4900 }  # Legacy data should be ignored
    )

    # Should use object (failed), not data (succeeded)
    assert_not charge.succeeded?
  end

  test "succeeded? returns true when amount_captured matches amount (legacy Pay)" do
    charge = Pay::Charge.new(
      type: "Pay::Stripe::Charge",
      amount: 4900,
      data: { amount_captured: 4900 }
    )

    assert charge.succeeded?
  end

  test "succeeded? returns true by default for non-Stripe charges" do
    # Use Pay::Charge base class (not a non-existent subclass) to avoid STI errors
    charge = Pay::Charge.new(type: "Pay::Charge")

    assert charge.succeeded?
  end

  test "charge_object_data returns object when present (Pay 10+)" do
    charge = Pay::Charge.new(
      object: { "status" => "succeeded", "id" => "ch_123" },
      data: { "status" => "failed" }
    )

    result = charge.send(:charge_object_data)
    assert_equal "succeeded", result["status"]
    assert_equal "ch_123", result["id"]
  end

  test "charge_object_data returns data when object is empty (legacy Pay)" do
    charge = Pay::Charge.new(
      object: {},
      data: { "status" => "succeeded", "id" => "ch_456" }
    )

    result = charge.send(:charge_object_data)
    assert_equal "succeeded", result["status"]
    assert_equal "ch_456", result["id"]
  end

  test "charge_object_data returns empty hash when both are empty" do
    charge = Pay::Charge.new(object: {}, data: {})

    result = charge.send(:charge_object_data)
    assert_equal({}, result.to_h)
  end

  test "charge_object_data returns data when object is nil (not just empty)" do
    # Some older Pay versions might have nil instead of empty hash
    charge = Pay::Charge.new(
      object: nil,
      data: { "status" => "succeeded", "id" => "ch_nil_object" }
    )

    result = charge.send(:charge_object_data)
    assert_equal "succeeded", result["status"]
    assert_equal "ch_nil_object", result["id"]
  end

  # ========================================
  # SUCCEEDED? - ALL STATUS VALUES
  # ========================================
  # GitHub Issue #1: https://github.com/rameerez/usage_credits/issues/1
  # These tests cover all Stripe charge status values

  test "succeeded? returns false for status pending in object (Pay 10+)" do
    charge = Pay::Charge.new(
      type: "Pay::Stripe::Charge",
      amount: 4900,
      object: { "status" => "pending", "amount_captured" => 0 },
      data: {}
    )

    assert_not charge.succeeded?
  end

  test "succeeded? returns false for status canceled in object (Pay 10+)" do
    charge = Pay::Charge.new(
      type: "Pay::Stripe::Charge",
      amount: 4900,
      object: { "status" => "canceled", "amount_captured" => 0 },
      data: {}
    )

    assert_not charge.succeeded?
  end

  test "succeeded? returns false for status pending in data (legacy Pay)" do
    charge = Pay::Charge.new(
      type: "Pay::Stripe::Charge",
      amount: 4900,
      object: {},
      data: { "status" => "pending", "amount_captured" => 0 }
    )

    assert_not charge.succeeded?
  end

  test "succeeded? returns true when status is nil but amount_captured matches (fallback)" do
    # Edge case: status not present but amount_captured equals amount
    charge = Pay::Charge.new(
      type: "Pay::Stripe::Charge",
      amount: 4900,
      object: { "amount_captured" => 4900 },  # No status field
      data: {}
    )

    assert charge.succeeded?
  end

  test "succeeded? returns false when status is nil and amount_captured is zero" do
    charge = Pay::Charge.new(
      type: "Pay::Stripe::Charge",
      amount: 4900,
      object: { "amount_captured" => 0 },  # No status, no capture
      data: {}
    )

    assert_not charge.succeeded?
  end

  test "succeeded? returns false when status is nil and amount_captured differs from amount" do
    # Partial capture scenario
    charge = Pay::Charge.new(
      type: "Pay::Stripe::Charge",
      amount: 4900,
      object: { "amount_captured" => 2000 },  # Only partially captured
      data: {}
    )

    assert_not charge.succeeded?
  end

  # ========================================
  # PAY 10+ INTEGRATION - ISSUE #1 EXACT SCENARIO
  # ========================================
  # This test replicates the exact scenario reported in GitHub Issue #1:
  # - User @onurozer reported Pay::Charge.last.data["status"] returns nil
  # - But charge.object["status"] returns "succeeded"
  # - Credits were not being fulfilled because code checked data["status"]

  test "Pay 10+ integration: credits ARE fulfilled when status is in object column (Issue #1 fix)" do
    # This is the EXACT scenario from Issue #1:
    # - charge.data["status"] returns nil
    # - charge.object["status"] returns "succeeded"

    user = User.create!(email: "pay10_integration@example.com", name: "Pay 10+ User")
    wallet = user.credit_wallet

    customer = Pay::Customer.create!(
      owner: user,
      processor: :fake_processor,
      processor_id: "cus_pay10_integration"
    )

    # Simulate Pay 10+ behavior: full Stripe object in `object`, empty `data`
    charge = Pay::Charge.create!(
      customer: customer,
      type: "Pay::Stripe::Charge",  # Use Stripe charge type
      processor_id: "ch_pay10_integration",
      amount: 4900,
      currency: "usd",
      amount_refunded: 0,
      metadata: {
        purchase_type: "credit_pack",
        pack_name: "starter",
        credits: 1000,
        price_cents: 4900
      },
      # Pay 10+ stores full Stripe charge object here
      object: {
        "id" => "ch_pay10_integration",
        "status" => "succeeded",
        "amount" => 4900,
        "amount_captured" => 4900,
        "paid" => true,
        "captured" => true
      },
      # In Pay 10+, data only contains store_accessor fields, NOT status
      data: {
        # NO "status" key here - this is the root cause of Issue #1
        "stripe_receipt_url" => "https://example.com/receipt"
      }
    )

    # Verify the exact scenario from Issue #1
    assert_nil charge.data["status"], "data['status'] should be nil (as reported in Issue #1)"
    assert_equal "succeeded", charge.object["status"], "object['status'] should be 'succeeded'"

    # The fix ensures succeeded? now checks object column
    assert charge.succeeded?, "succeeded? should return true when object['status'] is 'succeeded'"

    # Credits MUST be fulfilled
    assert_equal 1000, wallet.reload.credits, "Credits should be fulfilled when object['status'] is 'succeeded'"
  end

  test "Pay 10+ integration: credits NOT fulfilled when status is failed in object column" do
    user = User.create!(email: "pay10_failed@example.com", name: "Pay 10+ Failed User")
    wallet = user.credit_wallet

    customer = Pay::Customer.create!(
      owner: user,
      processor: :fake_processor,
      processor_id: "cus_pay10_failed"
    )

    # Simulate Pay 10+ behavior with failed charge
    Pay::Charge.create!(
      customer: customer,
      type: "Pay::Stripe::Charge",
      processor_id: "ch_pay10_failed",
      amount: 4900,
      currency: "usd",
      amount_refunded: 0,
      metadata: {
        purchase_type: "credit_pack",
        pack_name: "starter",
        credits: 1000
      },
      object: {
        "id" => "ch_pay10_failed",
        "status" => "failed",
        "amount" => 4900,
        "amount_captured" => 0,
        "paid" => false,
        "failure_message" => "Card declined"
      },
      data: {}
    )

    # Credits should NOT be added for failed charges
    assert_equal 0, wallet.reload.credits, "Credits should NOT be fulfilled for failed charges"
  end

  test "refunded? returns true when amount_refunded is positive" do
    charge = pay_charges(:refunded_charge)

    assert charge.refunded?
  end

  test "refunded? returns false when amount_refunded is zero" do
    charge = pay_charges(:completed_charge)

    assert_not charge.refunded?
  end

  test "refunded? returns false when amount_refunded is nil" do
    charge = Pay::Charge.new(amount_refunded: nil)

    assert_not charge.refunded?
  end

  test "is_credit_pack_purchase? returns true when purchase_type is credit_pack" do
    charge = pay_charges(:completed_charge)

    assert charge.send(:is_credit_pack_purchase?)
  end

  test "is_credit_pack_purchase? returns false when purchase_type is different" do
    charge = pay_charges(:non_pack_charge)

    assert_not charge.send(:is_credit_pack_purchase?)
  end

  test "pack_identifier returns pack_name from metadata" do
    charge = pay_charges(:completed_charge)

    assert_equal "starter", charge.send(:pack_identifier)
  end

  test "has_valid_wallet? returns true when customer owner has credit_wallet" do
    charge = pay_charges(:completed_charge)

    assert charge.send(:has_valid_wallet?)
  end

  test "has_valid_wallet? returns false when customer is nil" do
    charge = Pay::Charge.new(customer: nil)

    assert_not charge.send(:has_valid_wallet?)
  end

  test "credit_wallet returns customer owner's credit_wallet" do
    charge = pay_charges(:completed_charge)
    wallet = charge.send(:credit_wallet)

    assert_not_nil wallet
    assert_equal users(:rich_user), wallet.owner
  end

  # ========================================
  # CREDIT PACK FULFILLMENT - SUCCESS CASES
  # ========================================

  test "successful charge fulfillment logic works" do
    # Create a fresh user to avoid fixture wallet conflicts
    user = User.create!(email: "fulfill_test@example.com", name: "Fulfill Test User")
    wallet = user.credit_wallet  # Auto-created wallet

    customer = Pay::Customer.create!(
      owner: user,
      processor: :fake_processor,
      processor_id: "cus_test_fulfill"
    )

    charge = Pay::Charge.create!(
      customer: customer,
      type: "Pay::Charge",
      processor_id: "ch_fulfill_test",
      amount: 4900,
      currency: "usd",
      amount_refunded: 0,
      metadata: {
        purchase_type: "credit_pack",
        pack_name: "starter",
        credits: 1000,
        price_cents: 4900
      },
      data: {
        status: "succeeded",
        amount_captured: 4900,
        paid: true
      }
    )

    # Test that the charge has the right properties for fulfillment
    assert charge.send(:is_credit_pack_purchase?)
    assert_equal "starter", charge.send(:pack_identifier)
    assert charge.send(:has_valid_wallet?)
    assert charge.send(:succeeded?)
    refute charge.send(:refunded?)

    # After commit, credits should be added
    assert_equal 1000, wallet.reload.credits
  end

  test "charge creates fulfillment record" do
    # Create a fresh user to avoid fixture wallet conflicts
    user = User.create!(email: "fulfill2_test@example.com", name: "Fulfill2 Test User")
    user.credit_wallet  # Ensure wallet exists

    customer = Pay::Customer.create!(
      owner: user,
      processor: :fake_processor,
      processor_id: "cus_test_fulfill2"
    )

    assert_difference "UsageCredits::Fulfillment.count", 1 do
      charge = Pay::Charge.create!(
        customer: customer,
        type: "Pay::Charge",
        processor_id: "ch_fulfill_test2",
        amount: 4900,
        currency: "usd",
        amount_refunded: 0,
        metadata: {
          purchase_type: "credit_pack",
          pack_name: "starter",
          credits: 1000,
          price_cents: 4900
        },
        data: { status: "succeeded" }
      )

      fulfillment = UsageCredits::Fulfillment.find_by(source: charge)
      assert_not_nil fulfillment
      assert_equal "credit_pack", fulfillment.fulfillment_type
      assert_equal 1000, fulfillment.credits_last_fulfillment
      assert_nil fulfillment.next_fulfillment_at  # One-time, not recurring
    end
  end

  test "pack with bonus credits awards total credits" do
    # Create a fresh user to avoid fixture wallet conflicts
    user = User.create!(email: "bonus_test@example.com", name: "Bonus Test User")
    wallet = user.credit_wallet  # Auto-created wallet

    customer = Pay::Customer.create!(
      owner: user,
      processor: :fake_processor,
      processor_id: "cus_test_bonus"
    )

    assert_difference -> { wallet.reload.credits }, 600 do  # 500 + 100 bonus
      Pay::Charge.create!(
        customer: customer,
        type: "Pay::Charge",
        processor_id: "ch_bonus_test",
        amount: 2900,
        currency: "usd",
        metadata: {
          purchase_type: "credit_pack",
          pack_name: "bonus_pack",
          credits: 500,
          bonus_credits: 100,
          price_cents: 2900
        },
        data: { status: "succeeded" }
      )
    end
  end

  test "transaction metadata includes charge information" do
    # Create a fresh user to avoid fixture wallet conflicts
    user = User.create!(email: "metadata_test@example.com", name: "Metadata Test User")
    wallet = user.credit_wallet  # Auto-created wallet

    customer = Pay::Customer.create!(
      owner: user,
      processor: :fake_processor,
      processor_id: "cus_test_metadata"
    )

    charge = Pay::Charge.create!(
      customer: customer,
      type: "Pay::Charge",
      processor_id: "ch_metadata_test",
      amount: 4900,
      currency: "usd",
      metadata: {
        purchase_type: "credit_pack",
        pack_name: "starter",
        credits: 1000,
        price_cents: 4900
      },
      data: { status: "succeeded" }
    )

    transaction = wallet.transactions.find_by(category: "credit_pack_purchase")
    assert_not_nil transaction
    assert_equal charge.id, transaction.metadata["purchase_charge_id"]
    assert_equal true, transaction.metadata["credits_fulfilled"]
    assert_not_nil transaction.metadata["fulfilled_at"]
    assert_equal "starter", transaction.metadata["pack_name"]
  end

  # ========================================
  # CREDIT PACK FULFILLMENT - GUARD CLAUSES
  # ========================================

  test "non credit pack charge is ignored" do
    # Use fixture user with existing wallet
    user = users(:new_user)
    wallet = user.credit_wallet

    customer = Pay::Customer.create!(
      owner: user,
      processor: :fake_processor,
      processor_id: "cus_test_nonpack"
    )

    assert_no_difference -> { wallet.reload.credits } do
      Pay::Charge.create!(
        customer: customer,
        type: "Pay::Charge",
        processor_id: "ch_nonpack_test",
        amount: 1999,
        currency: "usd",
        metadata: { product: "other_product" },
        data: { status: "succeeded" }
      )
    end
  end

  test "charge without pack_name is ignored" do
    # Use fixture user with existing wallet
    user = users(:new_user)
    wallet = user.credit_wallet

    customer = Pay::Customer.create!(
      owner: user,
      processor: :fake_processor,
      processor_id: "cus_test_no_pack_name"
    )

    assert_no_difference -> { wallet.reload.credits } do
      Pay::Charge.create!(
        customer: customer,
        type: "Pay::Charge",
        processor_id: "ch_no_pack_name",
        amount: 4900,
        currency: "usd",
        metadata: { purchase_type: "credit_pack" },  # Missing pack_name
        data: { status: "succeeded" }
      )
    end
  end

  test "charge for customer without wallet is ignored" do
    # Create user and immediately destroy wallet to test "no wallet" scenario
    user = User.create!(email: "nowallet@example.com", name: "No Wallet User")
    user.credit_wallet.destroy!  # Destroy the auto-created wallet
    user.reload  # Clear association cache

    customer = Pay::Customer.create!(
      owner: user,
      processor: :fake_processor,
      processor_id: "cus_test_no_wallet"
    )

    # Verify no wallet exists
    assert_nil user.original_credit_wallet

    assert_no_difference "UsageCredits::Transaction.count" do
      Pay::Charge.create!(
        customer: customer,
        type: "Pay::Charge",
        processor_id: "ch_no_wallet",
        amount: 4900,
        currency: "usd",
        metadata: {
          purchase_type: "credit_pack",
          pack_name: "starter",
          credits: 1000
        },
        data: { status: "succeeded" }
      )
    end
  end

  test "failed charge does not award credits" do
    # Use fixture user with existing wallet
    user = users(:new_user)
    wallet = user.credit_wallet

    customer = Pay::Customer.create!(
      owner: user,
      processor: :fake_processor,
      processor_id: "cus_test_failed"
    )

    assert_no_difference -> { wallet.reload.credits } do
      Pay::Charge.create!(
        customer: customer,
        type: "Pay::Stripe::Charge",
        processor_id: "ch_failed_test",
        amount: 4900,
        currency: "usd",
        metadata: {
          purchase_type: "credit_pack",
          pack_name: "starter",
          credits: 1000
        },
        data: { status: "failed", amount_captured: 0 }
      )
    end
  end

  test "refunded charge does not award credits on creation" do
    # Use fixture user with existing wallet
    user = users(:new_user)
    wallet = user.credit_wallet

    customer = Pay::Customer.create!(
      owner: user,
      processor: :fake_processor,
      processor_id: "cus_test_prerefunded"
    )

    assert_no_difference -> { wallet.reload.credits } do
      Pay::Charge.create!(
        customer: customer,
        type: "Pay::Charge",
        processor_id: "ch_prerefunded",
        amount: 4900,
        currency: "usd",
        amount_refunded: 4900,  # Already refunded
        metadata: {
          purchase_type: "credit_pack",
          pack_name: "starter",
          credits: 1000
        },
        data: { status: "succeeded", refunded: true }
      )
    end
  end

  # ========================================
  # IDEMPOTENCY - DUPLICATE FULFILLMENT PREVENTION
  # ========================================

  test "already fulfilled charge does not award credits again" do
    # Create a fresh user to avoid fixture wallet conflicts
    user = User.create!(email: "idempotent_test@example.com", name: "Idempotent Test User")
    wallet = user.credit_wallet  # Auto-created wallet

    customer = Pay::Customer.create!(
      owner: user,
      processor: :fake_processor,
      processor_id: "cus_test_duplicate"
    )

    # Create charge and fulfill it
    charge = Pay::Charge.create!(
      customer: customer,
      type: "Pay::Charge",
      processor_id: "ch_duplicate_test",
      amount: 4900,
      currency: "usd",
      metadata: {
        purchase_type: "credit_pack",
        pack_name: "starter",
        credits: 1000
      },
      data: { status: "succeeded" }
    )

    # Credits should now be 1000
    assert_equal 1000, wallet.reload.credits

    # Manually trigger fulfill again - should not add more credits
    assert_no_difference -> { wallet.reload.credits } do
      charge.send(:fulfill_credit_pack!)
    end
  end

  test "credits_already_fulfilled? detects via fulfillment record" do
    # Create a fresh user to avoid fixture wallet conflicts
    user = User.create!(email: "fulfilled_check@example.com", name: "Fulfilled Check User")
    user.credit_wallet  # Ensure wallet exists

    customer = Pay::Customer.create!(
      owner: user,
      processor: :fake_processor,
      processor_id: "cus_test_fulfilled_check"
    )

    charge = Pay::Charge.create!(
      customer: customer,
      type: "Pay::Charge",
      processor_id: "ch_fulfilled_check",
      amount: 4900,
      currency: "usd",
      metadata: {
        purchase_type: "credit_pack",
        pack_name: "starter",
        credits: 1000
      },
      data: { status: "succeeded" }
    )

    # After creation, should be fulfilled
    assert charge.send(:credits_already_fulfilled?)
  end

  test "credits_already_fulfilled? detects via transaction metadata" do
    charge = pay_charges(:completed_charge)

    # completed_charge has already been fulfilled (see fixtures)
    assert charge.send(:credits_already_fulfilled?)
  end

  # ========================================
  # PACK VALIDATION
  # ========================================

  test "charge with unknown pack name is ignored" do
    # Use fixture user with existing wallet
    user = users(:new_user)
    wallet = user.credit_wallet

    customer = Pay::Customer.create!(
      owner: user,
      processor: :fake_processor,
      processor_id: "cus_test_unknown_pack"
    )

    assert_no_difference -> { wallet.reload.credits } do
      Pay::Charge.create!(
        customer: customer,
        type: "Pay::Charge",
        processor_id: "ch_unknown_pack",
        amount: 4900,
        currency: "usd",
        metadata: {
          purchase_type: "credit_pack",
          pack_name: "nonexistent_pack",
          credits: 1000
        },
        data: { status: "succeeded" }
      )
    end
  end

  test "charge with mismatched credits is ignored" do
    # Use fixture user with existing wallet
    user = users(:new_user)
    wallet = user.credit_wallet

    customer = Pay::Customer.create!(
      owner: user,
      processor: :fake_processor,
      processor_id: "cus_test_mismatch"
    )

    assert_no_difference -> { wallet.reload.credits } do
      Pay::Charge.create!(
        customer: customer,
        type: "Pay::Charge",
        processor_id: "ch_mismatch",
        amount: 4900,
        currency: "usd",
        metadata: {
          purchase_type: "credit_pack",
          pack_name: "starter",
          credits: 999  # Starter pack should give 1000
        },
        data: { status: "succeeded" }
      )
    end
  end

  # ========================================
  # REFUND HANDLING - FULL REFUND
  # ========================================

  test "full refund deducts all credits" do
    # Create a fresh user to avoid fixture wallet conflicts
    user = User.create!(email: "full_refund@example.com", name: "Full Refund User")
    wallet = user.credit_wallet  # Auto-created wallet

    customer = Pay::Customer.create!(
      owner: user,
      processor: :fake_processor,
      processor_id: "cus_test_full_refund"
    )

    # Create and fulfill charge
    charge = Pay::Charge.create!(
      customer: customer,
      type: "Pay::Charge",
      processor_id: "ch_full_refund",
      amount: 4900,
      currency: "usd",
      amount_refunded: 0,
      metadata: {
        purchase_type: "credit_pack",
        pack_name: "starter",
        credits: 1000
      },
      data: { status: "succeeded" }
    )

    assert_equal 1000, wallet.reload.credits

    # Now refund it fully
    assert_difference -> { wallet.reload.credits }, -1000 do
      charge.update!(amount_refunded: 4900)
    end
  end

  test "full refund creates refund transaction with metadata" do
    # Create a fresh user to avoid fixture wallet conflicts
    user = User.create!(email: "refund_tx@example.com", name: "Refund TX User")
    wallet = user.credit_wallet  # Auto-created wallet

    customer = Pay::Customer.create!(
      owner: user,
      processor: :fake_processor,
      processor_id: "cus_test_refund_tx"
    )

    charge = Pay::Charge.create!(
      customer: customer,
      type: "Pay::Charge",
      processor_id: "ch_refund_tx",
      amount: 4900,
      currency: "usd",
      amount_refunded: 0,
      metadata: {
        purchase_type: "credit_pack",
        pack_name: "starter",
        credits: 1000
      },
      data: { status: "succeeded" }
    )

    charge.update!(amount_refunded: 4900)

    refund_tx = wallet.transactions.find_by(category: "credit_pack_refund")
    assert_not_nil refund_tx
    assert_equal(-1000, refund_tx.amount)
    assert_equal charge.id, refund_tx.metadata["refunded_purchase_charge_id"]
    assert_equal true, refund_tx.metadata["credits_refunded"]
    assert_equal 1.0, refund_tx.metadata["refund_percentage"]
    assert_equal 4900, refund_tx.metadata["refund_amount_cents"]
  end

  # ========================================
  # REFUND HANDLING - PARTIAL REFUND
  # ========================================

  test "partial refund deducts proportional credits" do
    # Create a fresh user to avoid fixture wallet conflicts
    user = User.create!(email: "partial_refund@example.com", name: "Partial Refund User")
    wallet = user.credit_wallet  # Auto-created wallet

    customer = Pay::Customer.create!(
      owner: user,
      processor: :fake_processor,
      processor_id: "cus_test_partial"
    )

    charge = Pay::Charge.create!(
      customer: customer,
      type: "Pay::Charge",
      processor_id: "ch_partial_refund",
      amount: 4900,
      currency: "usd",
      amount_refunded: 0,
      metadata: {
        purchase_type: "credit_pack",
        pack_name: "starter",
        credits: 1000
      },
      data: { status: "succeeded" }
    )

    assert_equal 1000, wallet.reload.credits

    # Refund 50% (2450 cents)
    # Should deduct ceil(1000 * 0.5) = 500 credits
    assert_difference -> { wallet.reload.credits }, -500 do
      charge.update!(amount_refunded: 2450)
    end
  end

  test "partial refund uses ceil for credit calculation" do
    # Create a fresh user to avoid fixture wallet conflicts
    user = User.create!(email: "ceil_test@example.com", name: "Ceil Test User")
    wallet = user.credit_wallet  # Auto-created wallet

    customer = Pay::Customer.create!(
      owner: user,
      processor: :fake_processor,
      processor_id: "cus_test_ceil"
    )

    charge = Pay::Charge.create!(
      customer: customer,
      type: "Pay::Charge",
      processor_id: "ch_ceil_test",
      amount: 4900,
      currency: "usd",
      amount_refunded: 0,
      metadata: {
        purchase_type: "credit_pack",
        pack_name: "starter",
        credits: 1000
      },
      data: { status: "succeeded" }
    )

    # Refund 30% (1470 cents) should deduct ceil(1000 * 0.3) = 300 credits
    assert_difference -> { wallet.reload.credits }, -300 do
      charge.update!(amount_refunded: 1470)
    end
  end

  test "multiple partial refunds accumulate correctly" do
    # Create a fresh user to avoid fixture wallet conflicts
    user = User.create!(email: "multi_refund@example.com", name: "Multi Refund User")
    wallet = user.credit_wallet  # Auto-created wallet

    customer = Pay::Customer.create!(
      owner: user,
      processor: :fake_processor,
      processor_id: "cus_test_multi_refund"
    )

    charge = Pay::Charge.create!(
      customer: customer,
      type: "Pay::Charge",
      processor_id: "ch_multi_refund",
      amount: 4900,
      currency: "usd",
      amount_refunded: 0,
      metadata: {
        purchase_type: "credit_pack",
        pack_name: "starter",
        credits: 1000
      },
      data: { status: "succeeded" }
    )

    initial_credits = wallet.reload.credits

    # First refund: 25% (1225 cents) = ceil(250) = 250 credits
    charge.update!(amount_refunded: 1225)
    assert_equal initial_credits - 250, wallet.reload.credits

    # Second refund: another 25% (total 50%) = ceil(250) = 250 more credits
    charge.update!(amount_refunded: 2450)
    assert_equal initial_credits - 500, wallet.reload.credits
  end

  # ========================================
  # REFUND HANDLING - EDGE CASES
  # ========================================

  test "refund when credits already spent raises InsufficientCredits" do
    # Create a fresh user to avoid fixture wallet conflicts
    user = User.create!(email: "insufficient@example.com", name: "Insufficient User")
    wallet = user.credit_wallet  # Auto-created wallet

    customer = Pay::Customer.create!(
      owner: user,
      processor: :fake_processor,
      processor_id: "cus_test_insufficient"
    )

    charge = Pay::Charge.create!(
      customer: customer,
      type: "Pay::Charge",
      processor_id: "ch_insufficient",
      amount: 4900,
      currency: "usd",
      amount_refunded: 0,
      metadata: {
        purchase_type: "credit_pack",
        pack_name: "starter",
        credits: 1000
      },
      data: { status: "succeeded" }
    )

    # Verify credits were added
    assert_equal 1000, wallet.reload.credits

    # Spend all credits
    wallet.deduct_credits(1000, category: "operation_charge", metadata: {})
    assert_equal 0, wallet.reload.credits

    # Try to refund - should raise InsufficientCredits
    assert_raises(UsageCredits::InsufficientCredits) do
      charge.update!(amount_refunded: 4900)
    end
  end

  test "refund without pack_name is ignored" do
    # Use fixture user with existing wallet
    user = users(:new_user)
    wallet = user.credit_wallet

    customer = Pay::Customer.create!(
      owner: user,
      processor: :fake_processor,
      processor_id: "cus_test_no_pack_refund"
    )

    # Create charge without pack_name (shouldn't have been fulfilled anyway)
    charge = Pay::Charge.create!(
      customer: customer,
      type: "Pay::Charge",
      processor_id: "ch_no_pack_refund",
      amount: 4900,
      currency: "usd",
      amount_refunded: 0,
      metadata: { purchase_type: "credit_pack" },  # Missing pack_name
      data: { status: "succeeded" }
    )

    # Try to refund - should be ignored
    assert_no_difference -> { wallet.reload.credits } do
      charge.update!(amount_refunded: 4900)
    end
  end

  test "refund for customer without wallet is ignored" do
    # Create user and immediately destroy wallet to test "no wallet" scenario
    user = User.create!(email: "nowalletrefund@example.com", name: "No Wallet Refund")
    user.credit_wallet.destroy!  # Destroy the auto-created wallet
    user.reload  # Clear association cache

    customer = Pay::Customer.create!(
      owner: user,
      processor: :fake_processor,
      processor_id: "cus_test_no_wallet_refund"
    )

    charge = Pay::Charge.create!(
      customer: customer,
      type: "Pay::Charge",
      processor_id: "ch_no_wallet_refund",
      amount: 4900,
      currency: "usd",
      amount_refunded: 0,
      metadata: {
        purchase_type: "credit_pack",
        pack_name: "starter",
        credits: 1000
      },
      data: { status: "succeeded" }
    )

    # Try to refund - should be ignored (no wallet to deduct from)
    assert_no_difference "UsageCredits::Transaction.count" do
      charge.update!(amount_refunded: 4900)
    end
  end

  test "refund amount exceeding original charge is ignored" do
    # Create a fresh user to avoid fixture wallet conflicts
    user = User.create!(email: "excess_refund@example.com", name: "Excess Refund User")
    wallet = user.credit_wallet  # Auto-created wallet

    customer = Pay::Customer.create!(
      owner: user,
      processor: :fake_processor,
      processor_id: "cus_test_excess_refund"
    )

    charge = Pay::Charge.create!(
      customer: customer,
      type: "Pay::Charge",
      processor_id: "ch_excess_refund",
      amount: 4900,
      currency: "usd",
      amount_refunded: 0,
      metadata: {
        purchase_type: "credit_pack",
        pack_name: "starter",
        credits: 1000
      },
      data: { status: "succeeded" }
    )

    # Verify credits were added
    assert_equal 1000, wallet.reload.credits

    # Try to refund more than original amount - should be ignored
    assert_no_difference -> { wallet.reload.credits } do
      charge.update!(amount_refunded: 5000)  # More than 4900
    end
  end

  # ========================================
  # REFUND IDEMPOTENCY
  # ========================================

  test "already refunded charge does not process refund again" do
    # Create a fresh user to avoid fixture wallet conflicts
    user = User.create!(email: "refund_idempotent@example.com", name: "Refund Idempotent User")
    wallet = user.credit_wallet  # Auto-created wallet

    customer = Pay::Customer.create!(
      owner: user,
      processor: :fake_processor,
      processor_id: "cus_test_refund_idempotent"
    )

    charge = Pay::Charge.create!(
      customer: customer,
      type: "Pay::Charge",
      processor_id: "ch_refund_idempotent",
      amount: 4900,
      currency: "usd",
      amount_refunded: 0,
      metadata: {
        purchase_type: "credit_pack",
        pack_name: "starter",
        credits: 1000
      },
      data: { status: "succeeded" }
    )

    # Process refund
    charge.update!(amount_refunded: 4900)

    # Credits should now be 0
    assert_equal 0, wallet.reload.credits

    # Try to process refund again by manually calling the method
    assert_no_difference -> { wallet.reload.credits } do
      charge.send(:handle_refund!)
    end
  end

  test "credits_already_refunded? detects processed refund" do
    # Create a fresh user to avoid fixture wallet conflicts
    user = User.create!(email: "refund_check@example.com", name: "Refund Check User")
    user.credit_wallet  # Ensure wallet exists

    customer = Pay::Customer.create!(
      owner: user,
      processor: :fake_processor,
      processor_id: "cus_test_refund_check"
    )

    charge = Pay::Charge.create!(
      customer: customer,
      type: "Pay::Charge",
      processor_id: "ch_refund_check",
      amount: 4900,
      currency: "usd",
      amount_refunded: 0,
      metadata: {
        purchase_type: "credit_pack",
        pack_name: "starter",
        credits: 1000
      },
      data: { status: "succeeded" }
    )

    # Before refund
    assert_not charge.send(:credits_already_refunded?)

    # After refund
    charge.update!(amount_refunded: 4900)
    assert charge.send(:credits_already_refunded?)
  end

  # ========================================
  # INTEGRATION WITH EXISTING FIXTURES
  # ========================================

  test "completed_charge fixture has been fulfilled" do
    charge = pay_charges(:completed_charge)

    assert charge.send(:is_credit_pack_purchase?)
    assert charge.send(:credits_already_fulfilled?)
  end

  test "refunded_charge fixture has been refunded" do
    charge = pay_charges(:refunded_charge)

    assert charge.refunded?
    assert_equal 9900, charge.amount_refunded
  end

  test "partial_refund_charge fixture is partially refunded" do
    charge = pay_charges(:partial_refund_charge)

    assert charge.refunded?
    assert_equal 2450, charge.amount_refunded
    assert charge.amount_refunded < charge.amount
  end

  test "failed_charge fixture did not award credits" do
    charge = pay_charges(:failed_charge)

    assert_not charge.succeeded?
  end

  test "non_pack_charge fixture is not a credit pack purchase" do
    charge = pay_charges(:non_pack_charge)

    assert_not charge.send(:is_credit_pack_purchase?)
  end
end
