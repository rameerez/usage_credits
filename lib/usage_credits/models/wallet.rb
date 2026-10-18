# frozen_string_literal: true

module UsageCredits
  # A Wallet manages credit balance and transactions for a user/owner.
  #
  # This class extends Wallets::Wallet with usage_credits-specific features:
  #   - Operation-based spending (spend_credits_on)
  #   - Human-friendly API (give_credits, credits, credit_history)
  #   - Fulfillment tracking for subscriptions and credit packs
  #   - Usage-credits specific callbacks (credits_added, credits_deducted, etc.)

  class Wallet < Wallets::WalletBase
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

      # One command, like every core command: the affordability check, the
      # protected operation and the debit share the wallet lock, one instant
      # and the core's verdict on this transaction's snapshot. Otherwise a
      # caller that read before spending could check a stale MySQL balance:
      # run the block on credits another request already took, or refuse
      # credits another request just added. Its own savepoint makes it whole
      # either way: a refused debit rolls back the block's writes too, even
      # when the caller rescues and commits.
      with_lock(requires_new: true) do
        mutating_at(Time.current) do
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
      raise InsufficientCredits, in_credits_terms(e.message)
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

      # A command like any other: its own savepoint, and one instant and one
      # snapshot verdict for every read. Outside the core's mutation context,
      # refreshing the cached balance on a stale MySQL snapshot would cache a
      # stale balance and bump `ledger_revision` unnoticed; the next command in
      # the same transaction would then see its own revision and trust the
      # stale snapshot.
      with_lock(requires_new: true) do
        mutating_at(Time.current) do
          previous_balance = balance
          transactions_to_expire = transactions.credits.where(fulfillment: fulfillment)
          expiry = transactions_to_expire.klass.arel_table[:expires_at]
          updated_count = transactions_to_expire
            .where(expiry.eq(nil).or(expiry.gt(expiration)))
            .update_all(expires_at: expiration, updated_at: evaluation_time)

          if updated_count.positive?
            new_balance = refresh_cached_balance!
            dispatch_balance_threshold_callbacks!(previous_balance, new_balance)
          end

          updated_count
        end
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
      raise InsufficientCredits, in_credits_terms(e.message)
    rescue Wallets::Error => e
      raise UsageCredits::Error, e.message
    end

    alias_method :transfer_credits_to, :transfer_to

    # The Pay charge extension's refund webhook handler calls this; it is not a
    # general-purpose API. Claws back a refund: the part of `total_credits`, what the refunds of
    # one purchase now add up to, that the ledger has not taken yet. The
    # block receives this wallet's refund debits and returns what earlier
    # refunds of the same purchase already took (nothing, without a block).
    # The lookup and the debit are one command, under the wallet lock, at one
    # instant and with one verdict on this transaction's snapshot, so the
    # refund debits are read as they are now. Outside the command the lookup
    # could miss a refund another connection committed after this
    # transaction's first read (Pay's commit callbacks run inside a
    # `transaction(joinable: false)`), and under MySQL's repeatable read the
    # same credits would be clawed back twice. The debit may be unbacked: a
    # refund is owed even after the purchased credits were spent, as ledger
    # debt that later credits repay while `credits` stays floored at zero.
    # Returns the refund transaction, or nil when nothing is outstanding.
    def deduct_refunded_credits(total_credits, metadata:, fulfillment:)
      with_lock(requires_new: true) do
        mutating_at(Time.current) do
          refunds = current_read(transactions.debits.where(category: "credit_pack_refund"), current_reads?)
          already_refunded = block_given? ? yield(refunds) : 0
          outstanding = total_credits - already_refunded
          next if outstanding <= 0

          apply_debit(
            outstanding,
            metadata: metadata.merge(incremental_credits: outstanding),
            category: :credit_pack_refund,
            transfer: nil,
            extra_attributes: {fulfillment: fulfillment},
            allow_unbacked: true
          )
        end
      end
    end

    private

    # The wallets core refuses in its own words ("Insufficient balance (5 <
    # 10)"); a credits wallet refuses in the words its own `InsufficientCredits`
    # already uses, whichever command raised it.
    def in_credits_terms(message)
      message.sub(/\AInsufficient balance\b/, "Insufficient credits")
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
