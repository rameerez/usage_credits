# frozen_string_literal: true

module UsageCredits
  # Manages credit balance and transactions for an owner
  class Wallet < ApplicationRecord
    self.table_name = "usage_credits_wallets"

    belongs_to :owner, polymorphic: true
    has_many :transactions, class_name: "UsageCredits::Transaction", dependent: :destroy

    validates :balance, numericality: { greater_than_or_equal_to: 0 }, unless: :allow_negative_balance?

    # Alias for more intuitive access
    def credits
      balance
    end

    def credit_history
      transactions.order(created_at: :asc)
    end

    def has_enough_credits_to?(operation_name, **params)
      operation = UsageCredits.operations[operation_name.to_sym]
      raise InvalidOperation, "Operation not found: #{operation_name}" unless operation

      # First validate the operation parameters
      operation.validate!(params)

      # Then check if we have enough credits
      credits >= operation.calculate_cost(params)
    rescue InvalidOperation => e
      raise e
    rescue StandardError => e
      raise InvalidOperation, "Error checking credits: #{e.message}"
    end

    def estimate_credits_to(operation_name, **params)
      operation = UsageCredits.operations[operation_name.to_sym]
      raise InvalidOperation, "Operation not found: #{operation_name}" unless operation

      # First validate the operation parameters
      operation.validate!(params)

      # Then calculate the cost
      operation.calculate_cost(params)
    rescue InvalidOperation => e
      raise e
    rescue StandardError => e
      raise InvalidOperation, "Error estimating cost: #{e.message}"
    end

    def spend_credits_on(operation_name, **params)
      operation = UsageCredits.operations[operation_name.to_sym]
      raise InvalidOperation, "Operation not found: #{operation_name}" unless operation

      # First validate the operation parameters
      operation.validate!(params)

      # Calculate cost
      cost = operation.calculate_cost(params)

      # Check if user has enough credits
      raise InsufficientCredits, "Insufficient credits (#{credits} < #{cost})" unless has_enough_credits_to?(operation_name, **params)

      deduct_params = {
        metadata: operation.to_audit_hash(params),
        category: :operation_charge
      }

      if block_given?
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

    def give_credits(amount, reason: nil)
      raise ArgumentError, "Cannot give negative credits" if amount.negative?

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

    # Internal methods for credit management
    def add_credits(amount, metadata: {}, category: :credit_added, expires_at: nil, source: nil)
      with_lock do
        self.balance += amount
        save!

        transactions.create!(
          amount: amount,
          category: category,
          metadata: metadata,
          expires_at: expires_at,
          source: source
        )

        notify_balance_change(:credits_added, amount)
      end
    end

    def deduct_credits(amount, metadata: {}, category: :credit_deducted, source: nil)
      with_lock do
        amount = amount.to_i
        raise InsufficientCredits, "Insufficient credits (#{credits} < #{amount})" if insufficient_credits?(amount)

        previous_balance = balance
        self.balance -= amount
        save!

        transactions.create!(
          amount: -amount,
          category: category,
          metadata: metadata,
          source: source
        )

        notify_balance_change(:credits_deducted, amount)
        check_low_balance if !was_low_balance?(previous_balance) && low_balance?
      end
    end

    private

    def insufficient_credits?(amount)
      !allow_negative_balance? && amount > credits
    end

    def allow_negative_balance?
      UsageCredits.configuration.allow_negative_balance
    end

    def notify_balance_change(event, amount)
      UsageCredits.handle_event(
        event,
        wallet: self,
        amount: amount,
        balance: credits
      )
    end

    def check_low_balance
      notify_balance_change(:low_balance_reached, credits)
    end

    def low_balance?
      threshold = UsageCredits.configuration.low_balance_threshold
      return false if threshold.nil?
      credits <= threshold
    end

    def was_low_balance?(previous_balance)
      threshold = UsageCredits.configuration.low_balance_threshold
      return false if threshold.nil?
      previous_balance <= threshold
    end
  end
end
