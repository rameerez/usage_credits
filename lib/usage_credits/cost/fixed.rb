# frozen_string_literal: true

module UsageCredits
  module Cost
    # Fixed credit cost (e.g., always costs 10 credits)
    class Fixed < Base
      attr_reader :period

      def initialize(amount)
        @amount = amount
        @period = nil
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

      # Support subscription plan period chaining
      def per(period)
        @period = period
        self
      end
    end
  end
end
