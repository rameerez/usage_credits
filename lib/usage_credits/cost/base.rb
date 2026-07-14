# frozen_string_literal: true

module UsageCredits
  module Cost
    # Base class for all credit cost calculations.
    # Subclasses implement different ways of calculating credit costs:
    # - Fixed: Simple fixed amount
    # - Variable: Amount based on units (MB, etc)
    # - Compound: Multiple costs added together
    class Base
      attr_reader :amount

      def initialize(amount)
        validate_amount!(amount) unless amount.is_a?(Proc)
        @amount = amount
      end

      def +(other)
        case other
        when Fixed, Variable
          Compound.new(self, other)
        else
          raise ArgumentError, "Cannot add #{other.class} to #{self.class}"
        end
      end

      def to_i
        calculate({})
      end

      protected

      def validate_amount!(amount)
        number = Wallets::WholeNumber.parse(amount, name: "Credit amount")
        if number.negative?
          raise ArgumentError, "Credit amount cannot be negative (got: #{amount})"
        end
      rescue ArgumentError => error
        raise if error.message.include?("cannot be negative")

        raise ArgumentError, "Credit amount must be a whole number (got: #{amount})"
      end
    end
  end
end
