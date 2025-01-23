# frozen_string_literal: true

module UsageCredits
  module Cost
    # Fixed credit cost (e.g., always costs 10 credits)
    class Fixed < Base
      def initialize(amount)
        @amount = amount
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
    end
  end
end
