# frozen_string_literal: true

module UsageCredits
  # Manages credit balance and transactions for an owner
  class Wallet < ApplicationRecord
    self.table_name = "usage_credits_wallets"

    belongs_to :owner, polymorphic: true
    has_many :transactions, class_name: "UsageCredits::Transaction", dependent: :destroy

    validates :balance, numericality: { greater_than_or_equal_to: 0 }, unless: :allow_negative_balance?
    validates :low_balance_threshold, numericality: { greater_than: 0 }, allow_nil: true

    # Alias for more intuitive access
    def credits
      balance
    end

    def credit_history
      transactions
    end

    def has_enough_credits_to?(operation_name, **params)
      operation = UsageCredits.operations[operation_name.to_sym]
      raise InvalidOperation, "Operation not found: #{operation_name}" unless operation

      credits >= operation.calculate_cost(params)
    end

    def estimate_credits_to(operation_name, **params)
      operation = UsageCredits.operations[operation_name.to_sym]
      raise InvalidOperation, "Operation not found: #{operation_name}" unless operation

      operation.calculate_cost(params)
    rescue InvalidOperation => e
      raise e
    rescue StandardError => e
      raise InvalidOperation, "Error estimating cost: #{e.message}"
    end

    def spend_credits_on(operation_name, **params)
      operation = UsageCredits.operations[operation_name.to_sym]
      raise InvalidOperation, "Operation not found: #{operation_name}" unless operation

      cost = operation.calculate_cost(params)
      operation.validate!(params)

      deduct_credits(
        cost,
        metadata: operation.to_audit_hash(params),
        category: :operation_charge
      )
    end

    def give_credits(amount, reason: nil)
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
        self.balance += amount.to_i
        save!

        transactions.create!(
          amount: amount.to_i,
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

        self.balance -= amount
        save!

        transactions.create!(
          amount: -amount,
          category: category,
          metadata: metadata,
          source: source
        )

        notify_balance_change(:credits_deducted, amount)
        check_low_balance
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
      UsageCredits.configuration.event_handler&.call(
        event,
        wallet: self,
        amount: amount,
        balance: credits
      )
    end

    def check_low_balance
      return unless low_balance? && UsageCredits.configuration.enable_alerts

      notify_balance_change(:low_balance_reached, credits)
    end

    def low_balance?
      return false if low_balance_threshold.nil?

      credits <= low_balance_threshold
    end
  end
end
