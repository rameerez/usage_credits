# frozen_string_literal: true

module UsageCredits
  # Centralized credit calculations used throughout the gem.
  # This ensures consistent rounding and credit math everywhere.
  module CreditCalculator
    module_function

    # Apply the configured rounding strategy to a credit amount
    # Always defaults to ceiling to ensure we never undercharge
    def apply_rounding(amount)
      case UsageCredits.configuration.rounding_strategy
      when :round
        amount.round
      when :floor
        amount.floor
      when :ceil
        amount.ceil
      else
        amount.ceil # Default to ceiling to never undercharge
      end
    end

    # Normalize every configured or dynamically calculated credit cost through
    # one strict boundary. Keeping parse-error translation here means fixed
    # values and Proc results cannot match Wallets error-message text in
    # separate places and drift apart.
    def normalize_credit_amount(amount)
      number = begin
        Wallets::WholeNumber.parse(amount, name: "Credit amount")
      rescue ArgumentError
        raise ArgumentError, "Credit amount must be a whole number (got: #{amount})"
      end

      if number.negative?
        raise ArgumentError, "Credit amount cannot be negative (got: #{amount})"
      end

      number
    end

    # Convert a monetary amount to credits
    def money_to_credits(cents, exchange_rate)
      apply_rounding(cents * exchange_rate / 100.0)
    end

    # Convert credits to a monetary amount
    def credits_to_money(credits, exchange_rate)
      apply_rounding(credits * 100.0 / exchange_rate)
    end
  end
end
