# frozen_string_literal: true

module UsageCredits
  # A Wallet manages credit balance and transactions for a user/owner.
  #
  # It's responsible for:
  #   1. Tracking credit balance
  #   2. Performing credit operations (add/deduct)
  #   3. Managing credit expiration
  #   4. Handling low balance alerts

  class Wallet < ApplicationRecord
    self.table_name = "usage_credits_wallets"

    # =========================================
    # Associations & Validations
    # =========================================

    belongs_to :owner, polymorphic: true
    has_many :transactions, class_name: "UsageCredits::Transaction", dependent: :destroy
    has_many :fulfillments, class_name: "UsageCredits::Fulfillment", dependent: :destroy

    validates :balance, numericality: { greater_than_or_equal_to: 0 }, unless: :allow_negative_balance?

    # =========================================
    # Credit Balance & History
    # =========================================

    # Get current credit balance as a sum of all non-expired credits
    def credits
      active_credits = transactions.not_expired.sum(:amount)
      [active_credits, 0].max  # Never return negative credits
    end

    # Get transaction history (oldest first)
    def credit_history
      transactions.order(created_at: :asc)
    end

    # =========================================
    # Credit Operations
    # =========================================

    # Check if wallet has enough credits for an operation
    def has_enough_credits_to?(operation_name, **params)
      operation = find_and_validate_operation(operation_name, params)

      # Then check if we actually have enough credits
      credits >= operation.calculate_cost(params)
    rescue InvalidOperation => e
      raise e
    rescue StandardError => e
      raise InvalidOperation, "Error checking credits: #{e.message}"
    end

    # Calculate how many credits an operation would cost
    def estimate_credits_to(operation_name, **params)
      operation = find_and_validate_operation(operation_name, params)

      # Then calculate the cost
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
      raise InsufficientCredits, "Insufficient credits (#{credits} < #{cost})" unless has_enough_credits_to?(operation_name, **params)

      # Create audit trail
      audit_data = operation.to_audit_hash(params)
      deduct_params = {
        metadata: audit_data.merge(operation.metadata).merge(
          "executed_at" => Time.current,
          "gem_version" => UsageCredits::VERSION
        ),
        category: :operation_charge
      }

      if block_given?
        # If block given, only deduct credits if it succeeds
        ActiveRecord::Base.transaction do
          lock!  # Row-level lock for concurrency safety

          yield  # Perform the operation first

          deduct_credits(cost, **deduct_params)  # Deduct credits only if the block was successful
        end
      else
        deduct_credits(cost, **deduct_params)
      end
    rescue StandardError => e
      raise e
    end

    # Give credits to the wallet
    # @param amount [Integer] Number of credits to give
    # @param reason [String] Why credits were given (for auditing)
    def give_credits(amount, reason: nil)
      raise ArgumentError, "Cannot give negative credits" if amount.negative?
      raise ArgumentError, "Credit amount must be a whole number" unless amount.integer?

      category = case reason&.to_s
                when "signup" then :signup_bonus
                when "referral" then :referral_bonus
                else :manual_adjustment
                end

      add_credits(
        amount,
        metadata: { reason: reason },
        category: category
      )
    end

    # =========================================
    # Credit Management (Internal API)
    # =========================================

    # Add credits to the wallet (internal method)
    def add_credits(amount, metadata: {}, category: :credit_added, expires_at: nil, fulfillment: nil)
      with_lock do
        amount = amount.to_i
        previous_balance = balance
        self.balance = credits + amount
        save!

        transaction = transactions.create!(
          amount: amount,
          category: category,
          expires_at: expires_at,
          metadata: metadata,
          fulfillment: fulfillment
        )

        notify_balance_change(:credits_added, amount)
        check_low_balance if !was_low_balance?(previous_balance) && low_balance?

        # To finish, let's return the transaction that has been just created so we can reference it in parts of the code
        # Useful, for example, to update the transaction's `fulfillment` reference in the subscription extension
        # after the credits have been awarded and the Fulfillment object has been created, we need to store it
        return transaction
      end
    end

    # Remove credits from the wallet (Internal method)
    def deduct_credits(amount, metadata: {}, category: :credit_deducted)
      with_lock do
        amount = amount.to_i
        raise InsufficientCredits, "Insufficient credits (#{credits} < #{amount})" if insufficient_credits?(amount)

        previous_balance = balance
        self.balance = credits - amount
        save!

        transactions.create!(
          amount: -amount,
          category: category,
          metadata: metadata
        )

        notify_balance_change(:credits_deducted, amount)
        check_low_balance if !was_low_balance?(previous_balance) && low_balance?
      end
    end

    private

    # =========================================
    # Helper Methods
    # =========================================

    # Find an operation and validate its parameters
    # @param name [Symbol] Operation name
    # @param params [Hash] Operation parameters to validate
    # @return [Operation] The validated operation
    # @raise [InvalidOperation] If operation not found or validation fails
    def find_and_validate_operation(name, params)
      operation = UsageCredits.operations[name.to_sym]
      raise InvalidOperation, "Operation not found: #{name}" unless operation
      operation.validate!(params)
      operation
    end

    def insufficient_credits?(amount)
      !allow_negative_balance? && amount > credits
    end

    def allow_negative_balance?
      UsageCredits.configuration.allow_negative_balance
    end

    # =========================================
    # Balance Change Notifications
    # =========================================

    def notify_balance_change(event, amount)
      UsageCredits.handle_event(
        event,
        wallet: self,
        amount: amount,
        balance: credits
      )
    end

    def check_low_balance
      return unless low_balance?
      UsageCredits.handle_event(:low_balance_reached, wallet: self)
    end

    def low_balance?
      threshold = UsageCredits.configuration.low_balance_threshold
      return false if threshold.nil? || threshold.negative?
      credits <= threshold
    end

    def was_low_balance?(previous_balance)
      threshold = UsageCredits.configuration.low_balance_threshold
      return false if threshold.nil? || threshold.negative?
      previous_balance <= threshold
    end
  end

end
