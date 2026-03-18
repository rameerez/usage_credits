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
    has_many :transactions, class_name: "UsageCredits::Transaction", dependent: :destroy
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
          metadata: { reason: "initial_balance" }
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
      positive_remaining_balance
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
      operation = find_and_validate_operation(operation_name, params)
      credits >= operation.calculate_cost(params)
    rescue InvalidOperation => e
      raise e
    rescue StandardError => e
      raise InvalidOperation, "Error checking credits: #{e.message}"
    end

    # Calculate how many credits an operation would cost
    def estimate_credits_to(operation_name, **params)
      operation = find_and_validate_operation(operation_name, params)
      operation.calculate_cost(params)
    rescue InvalidOperation => e
      raise e
    rescue StandardError => e
      raise InvalidOperation, "Error estimating cost: #{e.message}"
    end

    # Spend credits on an operation
    # @param operation_name [Symbol] The operation to perform
    # @param params [Hash] Parameters for the operation
    # @yield Optional block that must succeed before credits are deducted
    def spend_credits_on(operation_name, **params)
      operation = find_and_validate_operation(operation_name, params)
      cost = operation.calculate_cost(params)

      # Check if user has enough credits
      unless has_enough_credits_to?(operation_name, **params)
        UsageCredits::Callbacks.dispatch(:insufficient_credits,
          wallet: self,
          amount: cost,
          operation_name: operation_name,
          metadata: {
            available: credits,
            required: cost,
            params: params
          }
        )
        raise InsufficientCredits, "Insufficient credits (#{credits} < #{cost})"
      end

      # Create audit trail
      audit_data = operation.to_audit_hash(params).deep_stringify_keys
      deduct_params = {
        metadata: audit_data.merge(operation.metadata.deep_stringify_keys).merge(
          "executed_at" => Time.current,
          "gem_version" => UsageCredits::VERSION
        ),
        category: :operation_charge
      }

      if block_given?
        ActiveRecord::Base.transaction do
          lock!
          yield
          deduct_credits(cost, **deduct_params)
        end
      else
        deduct_credits(cost, **deduct_params)
      end
    rescue StandardError => e
      raise e
    end

    # Give credits to the wallet with optional reason and expiration date
    # @param amount [Integer] Number of credits to give
    # @param reason [String, nil] Optional reason for giving credits
    # @param expires_at [DateTime, nil] Optional expiration date for the credits
    def give_credits(amount, reason: nil, expires_at: nil)
      raise ArgumentError, "Amount is required" if amount.nil?
      raise ArgumentError, "Cannot give negative credits" if amount.to_i.negative?
      raise ArgumentError, "Credit amount must be a whole number" unless amount == amount.to_i
      raise ArgumentError, "Expiration date must be a valid datetime" if expires_at && !expires_at.respond_to?(:to_datetime)
      raise ArgumentError, "Expiration date must be in the future" if expires_at && expires_at <= Time.current

      category = case reason&.to_s
                when "signup" then :signup_bonus
                when "referral" then :referral_bonus
                when /bonus/i then :bonus
                else :manual_adjustment
                end

      add_credits(
        amount.to_i,
        metadata: { reason: reason },
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
    def deduct_credits(amount, metadata: {}, category: :credit_deducted)
      debit(amount, metadata: metadata, category: category)
    rescue Wallets::InsufficientBalance => e
      raise InsufficientCredits, e.message
    end

    # Transfer credits to another wallet
    # Converts Wallets errors to usage_credits errors for backwards compatibility
    def transfer_credits_to(other_wallet, amount, category: :transfer, metadata: {})
      transfer_to(other_wallet, amount, category: category, metadata: metadata)
    rescue Wallets::InvalidTransfer => e
      raise InvalidTransfer, e.message
    rescue Wallets::InsufficientBalance => e
      raise InsufficientCredits, e.message
    end

    private

    # =========================================
    # Helper Methods
    # =========================================

    # Find an operation and validate its parameters
    def find_and_validate_operation(name, params)
      operation = UsageCredits.operations[name.to_sym]
      raise InvalidOperation, "Operation not found: #{name}" unless operation
      operation.validate!(params)
      operation
    end
  end
end
