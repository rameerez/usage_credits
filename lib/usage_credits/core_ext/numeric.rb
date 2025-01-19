# frozen_string_literal: true

require "active_support/core_ext/numeric"

class Numeric
  def credits
    UsageCredits::Cost::Fixed.new(self)
  end
  alias_method :credit, :credits

  def credits_per(unit)
    UsageCredits::Cost::Variable.new(self, unit)
  end
  alias_method :credit_per, :credits_per

  def dollars
    self * 100 # Convert to cents for payment processors
  end
  alias_method :dollar, :dollars

  def megabytes
    self * 1024 * 1024 # Convert to bytes
  end
  alias_method :megabyte, :megabytes
  alias_method :mb, :megabytes

  def days
    self * 24 * 60 * 60 # Convert to seconds
  end
  alias_method :day, :days

  def years
    self * 365 * 24 * 60 * 60 # Convert to seconds
  end
  alias_method :year, :years
end

module UsageCredits
  module Cost
    class Base
      attr_reader :amount

      def initialize(amount)
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
    end

    class Fixed < Base
      def calculate(params = {})
        amount
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
        amount * size
      end

      private

      def extract_size(params)
        case unit
        when :megabyte, :megabytes, :mb
          params.fetch(:size, 0).to_i
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
  end
end
