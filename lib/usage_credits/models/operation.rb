# frozen_string_literal: true

module UsageCredits
  # Defines operations that consume credits
  class Operation < ApplicationRecord
    self.table_name = "usage_credits_operations"

    validates :name, presence: true, uniqueness: true
    validates :base_cost, presence: true, numericality: { greater_than_or_equal_to: 0 }

    # DSL methods for operation definition
    class Builder
      attr_reader :name, :cost_calculator, :validation_rules, :metadata

      def initialize(name)
        @name = name
        @cost_calculator = ->(params) { 0 }
        @validation_rules = {}
        @metadata = {}
      end

      # More English-like cost definition
      def cost(amount_or_calculator)
        @cost_calculator = if amount_or_calculator.is_a?(UsageCredits::Amount)
          ->(_) { amount_or_calculator.to_i }
        else
          amount_or_calculator
        end
      end

      # More English-like validation
      def validate(condition, message = nil)
        @validation_rules[:custom] = [condition, message]
      end

      # Add metadata
      def meta(hash)
        @metadata.merge!(hash)
      end

      # Build the operation
      def build
        Operation.new(
          name: name,
          base_cost: 0, # We'll store the actual cost at calculation time
          cost_rules: { calculator: cost_calculator },
          validation_rules: validation_rules,
          metadata: metadata
        )
      end
    end

    # Calculate the total cost for this operation
    def calculate_cost(params)
      calculator = cost_rules["calculator"]
      return base_cost unless calculator.is_a?(Proc)

      total = calculator.call(normalize_params(params))
      apply_rounding(total)
    end

    # Validate operation parameters
    def validate!(params)
      normalized = normalize_params(params)

      validation_rules.each do |rule_type, rule|
        case rule_type
        when :custom
          validate_custom_rule(*rule, normalized)
        end
      end
    end

    private

    def normalize_params(params)
      # Convert various size parameters to a standard format
      size = params[:size_mb] || params[:size]&.to_i || params[:size_megabytes]
      params.merge(size: size)
    end

    def validate_custom_rule(condition, message, params)
      return unless condition.is_a?(Proc)

      result = condition.call(params)
      raise InvalidOperation, (message || "Operation validation failed") unless result
    end

    def apply_rounding(amount)
      case UsageCredits.configuration.rounding_strategy
      when :round
        amount.round
      when :floor
        amount.floor
      when :ceil
        amount.ceil
      else
        amount.round
      end
    end
  end
end
