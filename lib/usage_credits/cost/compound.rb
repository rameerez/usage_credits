# frozen_string_literal: true

module UsageCredits
  module Cost
    # Compound credit cost that adds multiple costs together
    # Example: base cost + per MB cost
    class Compound < Base
      attr_reader :costs

      def initialize(*costs)
        @costs = costs.flatten
      end

      def calculate(params = {})
        total = costs.sum { |cost| cost.calculate(params) }
        CreditCalculator.apply_rounding(total)
      end

      def +(other)
        case other
        when Fixed, Variable
          self.class.new(costs + [other])
        else
          raise ArgumentError, "Cannot add #{other.class} to #{self.class}"
        end
      end
    end

    def self.credits(amount)
      Fixed.new(amount)
    end

    class_eval do
      singleton_class.alias_method :credit, :credits
    end
  end
end
