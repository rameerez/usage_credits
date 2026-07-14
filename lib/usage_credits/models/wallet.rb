# frozen_string_literal: true

module UsageCredits
  # A Wallet manages credit balance and transactions for a user/owner.
  #
  # This class extends Wallets::Wallet with usage_credits-specific features:
  #   - Operation-based spending (spend_credits_on)
  #   - Human-friendly API (give_credits, credits, credit_history)
  #   - Fulfillment tracking for subscriptions and credit packs
  #   - Usage-credits specific callbacks (credits_added, credits_deducted, etc.)

  class Wallet < Wallets::Wallet
    # =========================================
    # Embeddability Configuration
    # =========================================

    self.embedded_table_name = "usage_credits_wallets"
    self.config_provider = -> { UsageCredits.configuration }
    self.callbacks_module = UsageCredits::Callbacks
    self.transaction_class_name = "UsageCredits::Transaction"
    self.allocation_class_name = "UsageCredits::Allocation"
    self.transfer_class_name = "UsageCredits::Transfer"
    self.additional_transaction_attribute_names = %i[fulfillment].freeze

    # Map base wallet events to usage_credits-specific event names
    self.callback_event_map = {
      credited: :credits_added,
      debited: :credits_deducted,
      insufficient: :insufficient_credits,
      low_balance: :low_balance_reached,
      depleted: :balance_depleted,
      transfer_completed: nil
    }.freeze

    # =========================================
    # Re-declare Associations with Correct Classes
    # =========================================

    # Override parent associations to use UsageCredits classes
    has_many :transactions,
      class_name: "UsageCredits::Transaction",
      inverse_of: :wallet,
      dependent: :destroy
    has_many :outgoing_transfers,
      class_name: "UsageCredits::Transfer",
      foreign_key: :from_wallet_id,
      dependent: :destroy,
      inverse_of: :from_wallet
    has_many :incoming_transfers,
      class_name: "UsageCredits::Transfer",
      foreign_key: :to_wallet_id,
      dependent: :destroy,
      inverse_of: :to_wallet

    # UsageCredits-specific associations
    has_many :fulfillments, class_name: "UsageCredits::Fulfillment", dependent: :destroy

    class << self
      private

      def initial_balance_credit_attributes
        {
          category: :manual_adjustment,
          metadata: {reason: "initial_balance"}
        }
      end
    end

    # =========================================
    # Backwards Compatibility API
    # =========================================

    # Get current credit balance (alias for balance)
    #
    # usage_credits historically floors negative balances to zero even when
    # allow_negative_balance is enabled. Keep that contract for backwards
    # compatibility, even though the shared wallets core can represent unbacked
    # negative debits explicitly.
    def credits
      balance
    end

    def current_balance
      # Wallets::Wallet#balance delegates dynamically to current_balance, so
      # this override is the active public balance implementation (not a dead
      # helper). Refund debits remain explicit ledger debt while the Usage
      # Credits compatibility view stays floored at zero.
      refund_debits = transactions.debits.where(category: "credit_pack_refund")
      [positive_remaining_balance - unbacked_negative_balance(refund_debits), 0].max
    end

    # Get transaction history (oldest first) - alias for history
    def credit_history
      history
    end

    # =========================================
    # Credit Operations (High-Level API)
    # =========================================

    # Check if wallet has enough credits for an operation
    def has_enough_credits_to?(operation_name, **params)
      operation = find_operation(operation_name)
      credits >= operation.calculate_cost(params)
    rescue InvalidOperation
      raise
    rescue => e
      raise InvalidOperation, "Error checking credits: #{e.message}"
    end

    # Calculate how many credits an operation would cost
    def estimate_credits_to(operation_name, **params)
      operation = find_operation(operation_name)
      operation.calculate_cost(params)
    rescue InvalidOperation
      raise
    rescue => e
      raise InvalidOperation, "Error estimating cost: #{e.message}"
    end

    # Spend credits on an operation
    # @param operation_name [Symbol] The operation to perform
    # @param params [Hash] Parameters for the operation
    # @yield Optional block that must succeed before credits are deducted
    def spend_credits_on(operation_name, **params)
      operation = find_operation(operation_name)
      cost = operation.calculate_cost(params)

      # Create audit trail
      audit_data = operation.to_audit_hash(params, cost: cost).deep_stringify_keys
      deduct_params = {
        metadata: audit_data,
        category: :operation_charge
      }

      # The affordability check and the protected operation must happen while
      # holding the same wallet lock. Otherwise another request can consume the
      # balance after the pre-check, causing this block's side effects to run
      # even though its eventual debit fails.
      with_lock do
        available = credits
        if cost > available
          UsageCredits::Callbacks.dispatch(:insufficient_credits,
            wallet: self,
            amount: cost,
            operation_name: operation_name,
            metadata: {
              available: available,
              required: cost,
              params: params
            })
          raise InsufficientCredits, "Insufficient credits (#{available} < #{cost})"
        end

        yield if block_given?

        # Free operations are a supported part of the DSL. There is no valid
        # zero-amount ledger transaction to record, so execute the block and
        # return nil without calling the strictly-positive debit primitive.
        cost.zero? ? nil : deduct_credits(cost, **deduct_params)
      end
    end

    # Give credits to the wallet with optional reason and expiration date
    # @param amount [Integer] Number of credits to give
    # @param reason [String, nil] Optional reason for giving credits
    # @param expires_at [DateTime, nil] Optional expiration date for the credits
    def give_credits(amount, reason: nil, expires_at: nil)
      category = case reason&.to_s
      when "signup" then :signup_bonus
      when "referral" then :referral_bonus
      when /bonus/i then :bonus
      else :manual_adjustment
      end

      add_credits(
        amount,
        metadata: {reason: reason},
        category: category,
        expires_at: expires_at
      )
    end

    # =========================================
    # Credit Management (Internal API)
    # =========================================

    # Add credits to the wallet (wraps parent's credit method)
    # Maintains backwards compatibility with fulfillment parameter
    def add_credits(amount, metadata: {}, category: :credit_added, expires_at: nil, fulfillment: nil)
      credit(
        amount,
        metadata: metadata,
        category: category,
        expires_at: expires_at,
        fulfillment: fulfillment
      )
    end

    # Remove credits from the wallet (wraps parent's debit method)
    # Converts Wallets::InsufficientBalance to InsufficientCredits for backwards compatibility
    def deduct_credits(amount, metadata: {}, category: :credit_deducted, fulfillment: nil)
      debit(amount, metadata: metadata, category: category, fulfillment: fulfillment)
    rescue Wallets::InsufficientBalance => e
      raise InsufficientCredits, e.message
    end

    # Shorten the lifetime of credits minted by one fulfillment and reconcile
    # the wallet through the same balance/callback internals as core mutations.
    # This keeps Pay lifecycle code out of Wallets' private implementation and
    # makes immediate cancellation expiry observable through low/depleted
    # callbacks after the surrounding transaction commits.
    def expire_fulfillment_credits!(fulfillment:, expires_at:)
      unless expires_at.respond_to?(:to_datetime)
        raise ArgumentError, "Expiration date must respond to to_datetime"
      end

      expiration = begin
        expires_at.to_datetime
      rescue
        raise ArgumentError, "Expiration date must be a valid date or time"
      end

      with_lock do
        previous_balance = balance
        transactions_to_expire = transactions.credits.where(fulfillment: fulfillment)
        expiry = transactions_to_expire.klass.arel_table[:expires_at]
        updated_count = transactions_to_expire
          .where(expiry.eq(nil).or(expiry.gt(expiration)))
          .update_all(expires_at: expiration, updated_at: Time.current)

        if updated_count.positive?
          refresh_cached_balance!
          dispatch_balance_threshold_callbacks!(previous_balance)
        end

        updated_count
      end
    end

    # Keep the inherited wallet primitive inside usage_credits' public error
    # hierarchy. Both transfer entry points share this implementation and the
    # complete wallets transfer surface, including expiration overrides.
    def transfer_to(other_wallet, amount, category: :transfer, metadata: {}, expiration_policy: nil, expires_at: nil)
      super
    rescue Wallets::InvalidTransfer => e
      raise InvalidTransfer, e.message
    rescue Wallets::InsufficientBalance => e
      raise InsufficientCredits, e.message
    rescue Wallets::Error => e
      raise UsageCredits::Error, e.message
    end

    alias_method :transfer_credits_to, :transfer_to

    private

    # Payment refunds must be represented even after the purchased credits
    # have been consumed. The unbacked debit remains ledger debt; the public
    # balance stays floored at zero until later credits repay that debt.
    def deduct_refunded_credits(amount, metadata:, fulfillment:)
      with_lock do
        apply_debit(
          amount,
          metadata: metadata,
          category: :credit_pack_refund,
          transfer: nil,
          extra_attributes: {fulfillment: fulfillment},
          allow_unbacked: true
        )
      end
    end

    # =========================================
    # Helper Methods
    # =========================================

    # Find an operation. `Operation#calculate_cost` owns parameter validation,
    # keeping validation and user-supplied cost code single-evaluation.
    def find_operation(name)
      operation = UsageCredits.operations[name.to_sym]
      raise InvalidOperation, "Operation not found: #{name}" unless operation
      operation
    end
  end
end
