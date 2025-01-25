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
