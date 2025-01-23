# frozen_string_literal: true

require "active_support/core_ext/numeric"

# This is what allows us to write things like `3.credits` in the DSL
# Then the actual cost gets calculated in the UsageCredits::Cost classes
# (Cost::Base, Cost::Fixed, Cost::Variable, Cost::Compound, etc.)
class Numeric
  def credits
    raise ArgumentError, "Credit amount must be a whole number (decimals are not allowed)" unless self == self.to_i
    raise ArgumentError, "Credit amount cannot be negative" if self.negative?
    UsageCredits::Cost::Fixed.new(self.to_i)
  end
  alias_method :credit, :credits

  def credits_per(unit)
    raise ArgumentError, "Credit cost rate must be a whole number (decimals are not allowed)" unless self == self.to_i

    # Convert common units to their base unit
    unit = case unit.to_s.downcase
           when "mb", "megabyte", "megabytes"
             :mb
           when "kb", "kilobyte", "kilobytes"
             :kb
           when "gb", "gigabyte", "gigabytes"
             :gb
           when "unit", "units"
             :units
           else
             unit.to_sym
           end

    UsageCredits::Cost::Variable.new(self, unit)
  end
  alias_method :credit_per, :credits_per

  def dollars
    self * 100 # Convert to cents for payment processors
  end
  alias_method :dollar, :dollars
end

# This is what allows us to write .credit amounts as Procs, like:
#   cost ->(params) { 2 * params[:variable] }.credits
class Proc
  def credits
    UsageCredits::Cost::Fixed.new(self)
  end
  alias_method :credit, :credits
end
