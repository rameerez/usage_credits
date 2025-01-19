# frozen_string_literal: true

module UsageCredits
  # Defines operations that consume credits
  class Operation
    attr_reader :name, :cost_calculator, :validation_rules, :metadata

    def initialize(name, &block)
      @name = name
      @cost_calculator = ->(params) { 0 }
      @validation_rules = []
      @metadata = {}
      instance_eval(&block) if block_given?
    end

    # DSL methods for operation definition
    def cost(amount_or_calculator)
      @cost_calculator = if amount_or_calculator.is_a?(UsageCredits::Amount)
        ->(_) { amount_or_calculator.to_i }
      else
        amount_or_calculator
      end
    end

    # More English-like validation
    def validate(condition, message = nil)
      @validation_rules << [condition, message || "Operation validation failed"]
    end

    # Add metadata
    def meta(hash)
      @metadata.merge!(hash)
    end

    # Calculate the total cost for this operation
    def calculate_cost(params = {})
      total = cost_calculator.call(normalize_params(params))
      apply_rounding(total)
    end

    # Validate operation parameters
    def validate!(params = {})
      normalized = normalize_params(params)

      validation_rules.each do |condition, message|
        next unless condition.is_a?(Proc)
        raise InvalidOperation, message unless condition.call(normalized)
      end
    end

    # Serialize the operation for audit purposes
    def to_audit_hash(params = {})
      {
        operation: name,
        cost: calculate_cost(params),
        params: params,
        metadata: metadata,
        executed_at: Time.current,
        gem_version: UsageCredits::VERSION
      }
    end

    private

    def normalize_params(params)
      params = params.symbolize_keys
      # Convert various size parameters to a standard format
      size = params[:size_mb] || params[:size]&.to_i || params[:size_megabytes]
      params.merge(size: size)
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
