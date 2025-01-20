# frozen_string_literal: true

require "active_support/core_ext/numeric"

class Numeric
  def credits
    raise ArgumentError, "Credit amount must be a whole number (decimals are not allowed)" unless self == self.to_i
    raise ArgumentError, "Credit amount cannot be negative" if self.negative?
    UsageCredits::Cost::Fixed.new(self.to_i)
  end
  alias_method :credit, :credits

  def credits_per(unit)
    raise ArgumentError, "Credit cost rate must be a whole number (decimals are not allowed)" unless self == self.to_i
    UsageCredits::Cost::Variable.new(self, unit)
  end
  alias_method :credit_per, :credits_per

  def dollars
    self * 100 # Convert to cents for payment processors
  end
  alias_method :dollar, :dollars
end

class Proc
  def credits
    UsageCredits::Cost::Fixed.new(self)
  end
  alias_method :credit, :credits
end

module UsageCredits
  module Cost
    class Base
      attr_reader :amount

      def initialize(amount)
        raise ArgumentError, "Credit amount must be a whole number" unless amount == amount.to_i
        @amount = amount.to_i
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

      # Always round up partial credits to the next integer
      # This ensures users are never charged less than the actual cost
      def ceil_credits(amount)
        amount.ceil
      end
    end

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
          raise ArgumentError, "Credit amount must be a whole number" unless value == value.to_i
          raise ArgumentError, "Credit amount cannot be negative" if value.negative?
          value.to_i
        end
      end
    end

    class Variable < Base
      attr_reader :unit

      def initialize(amount, unit)
        super(amount)
        @unit = unit.to_sym
      end

      def calculate(params = {})
        size = extract_size(params)
        # Round up to nearest integer to ensure we never charge fractional credits
        (amount * size).ceil
      end

      private

      def extract_size(params)
        case unit
        when :megabyte, :megabytes, :mb
          # Convert bytes to megabytes for calculation
          params.fetch(:size, 0).to_f / 1.megabyte
        else
          raise ArgumentError, "Unknown unit: #{unit}"
        end
      end
    end

    class Compound < Base
      attr_reader :costs

      def initialize(*costs)
        @costs = costs.flatten
      end

      def calculate(params = {})
        # Calculate each cost and sum them up
        costs.sum { |cost| cost.calculate(params) }
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
