# frozen_string_literal: true

class Numeric
  def credits
    UsageCredits::Amount.new(self)
  end
  alias_method :credit, :credits

  def dollars
    self * 100 # Convert to cents
  end
  alias_method :dollar, :dollars

  def credits_per(unit)
    case unit
    when :megabyte, :megabytes, :mb
      UsageCredits::Amount.new(self)
    else
      raise ArgumentError, "Unknown unit: #{unit}"
    end
  end

  def megabytes
    self
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
  class Amount
    attr_reader :value

    def initialize(value)
      @value = value
    end

    def +(other)
      self.class.new(value + other.value)
    end

    def *(other)
      self.class.new(value * other)
    end

    def per_month
      self
    end

    def per(unit)
      case unit
      when :month
        per_month
      else
        raise ArgumentError, "Unknown unit: #{unit}"
      end
    end

    def of_cancellation
      value
    end

    def rollover
      true
    end

    def to_i
      value.to_i
    end

    def to_s
      "#{value} credits"
    end

    def inspect
      "#<UsageCredits::Amount #{value} credits>"
    end
  end

  class TimeAmount
    attr_reader :seconds

    def initialize(seconds)
      @seconds = seconds
    end

    def of_cancellation
      @seconds
    end

    def to_i
      @seconds
    end
  end
end
