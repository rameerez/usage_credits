# frozen_string_literal: true

module UsageCredits
  # Defines operations that consume credits
  class Operation
    attr_reader :name, :cost_calculator, :validation_rules, :metadata

    def initialize(name, &block)
      @name = name
      @cost_calculator = Cost::Fixed.new(0)
      @validation_rules = []
      @metadata = {}
      instance_eval(&block) if block_given?
    end

    # DSL methods for operation definition
    def cost(amount_or_calculator)
      @cost_calculator = case amount_or_calculator
      when Cost::Base
        amount_or_calculator
      else
        Cost::Fixed.new(amount_or_calculator)
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
      normalized_params = normalize_params(params)
      validate!(normalized_params) # Validate before calculating cost

      total = cost_calculator.calculate(normalized_params)
      apply_rounding(total)
    end

    # Validate operation parameters
    def validate!(params = {})
      normalized = normalize_params(params)

      validation_rules.each do |condition, message|
        next unless condition.is_a?(Proc)

        begin
          result = condition.call(normalized)
          raise InvalidOperation, message unless result
        rescue StandardError => e
          raise InvalidOperation, "Validation error: #{e.message}"
        end
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

      # Handle Rails numeric extensions properly
      size = if params[:size].respond_to?(:to_i)
               params[:size].to_i
             elsif params[:size_mb]
               params[:size_mb].to_i
             elsif params[:size_megabytes]
               params[:size_megabytes].to_i
             end

      params.merge(
        size: size,
        size_mb: size,
        size_megabytes: size
      )
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
