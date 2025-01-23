# frozen_string_literal: true

module UsageCredits
  module Cost
    # Fixed credit cost (e.g., always costs 10 credits)
    class Fixed < Base
      attr_reader :period

      def initialize(amount)
        @amount = amount
        @period = nil  # Will default to 1.month in CreditSubscriptionPlan
      end

      def calculate(params = {})
        value = amount.is_a?(Proc) ? amount.call(params) : amount
        case value
        when UsageCredits::Cost::Fixed
          value.calculate(params)
        else
          validate_amount!(value)
          value.to_i
        end
      end

      # Set the recurring period for subscription plans
      # @param period [Symbol, ActiveSupport::Duration, nil] The period (e.g., :month, 2.months, 15.days)
      # @return [self]
      def every(period = nil)
        @period = period  # nil will default to 1.month in CreditSubscriptionPlan
        self
      end
    end
  end
end
