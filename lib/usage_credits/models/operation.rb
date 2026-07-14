# frozen_string_literal: true

module UsageCredits
  # A DSL to define an operation that consumes credits when performed.
  class Operation
    attr_reader :name,                # Operation identifier (e.g., :process_video)
      :cost_calculator,     # Lambda or Fixed that calculates credit cost
      :validation_rules,    # Array of [condition, message] pairs
      :metadata             # Custom data for your app's use

    def initialize(name, &block)
      @name = name
      @cost_calculator = Cost::Fixed.new(0)  # Default to free
      @validation_rules = []
      @metadata = {}
      instance_eval(&block) if block_given?
    end

    # =========================================
    # DSL Methods (used in initializer blocks)
    # =========================================

    # Set how many credits this operation costs
    #
    # @param amount_or_calculator [Integer, Lambda] Fixed amount or dynamic calculator
    #   costs 10                          # Fixed cost
    #   costs ->(params) { params[:mb] }  # Dynamic cost
    def costs(amount_or_calculator)
      @cost_calculator = case amount_or_calculator
      when Cost::Base
        amount_or_calculator
      else
        Cost::Fixed.new(amount_or_calculator)
      end
    end
    alias_method :cost, :costs

    # Add a validation rule for this operation
    # Example: can't process images bigger than 100MB
    #
    # @param condition [Lambda] Returns true if valid
    # @param message [String] Error message if invalid
    def validate(condition, message = nil)
      @validation_rules << [condition, message || "Operation validation failed"]
    end

    # Add custom metadata
    def meta(hash)
      @metadata = @metadata.merge(hash.transform_keys(&:to_s))
    end

    # =========================================
    # Cost Calculation
    # =========================================

    # Calculate how many credits this operation will cost
    # @param params [Hash] Operation parameters (e.g., file size)
    # @return [Integer] Number of credits
    def calculate_cost(params = {})
      normalized_params = normalize_params(params)
      validate!(normalized_params)  # Ensure params are valid before calculating

      # `costs` wraps every configured value (including a Proc) in a Cost
      # object, so there is one calculation/validation path here.
      total = cost_calculator.calculate(normalized_params)

      # Apply configured rounding strategy
      CreditCalculator.apply_rounding(total)
    end

    # =========================================
    # Validation
    # =========================================

    # Check if the operation can be performed
    # @param params [Hash] Operation parameters to validate
    # @raise [InvalidOperation] If validation fails
    def validate!(params = {})
      normalized = normalize_params(params)

      validation_rules.each do |condition, message|
        next unless condition.is_a?(Proc)

        begin
          result = condition.call(normalized)
          raise InvalidOperation, message unless result
        rescue => e
          raise InvalidOperation, "Validation error: #{e.message}"
        end
      end
    end

    # =========================================
    # Audit Trail
    # =========================================

    # Create an audit record of this operation
    def to_audit_hash(params = nil, cost: nil, **keyword_params)
      params = (params || {}).merge(keyword_params)

      {
        operation: name,
        cost: cost.nil? ? calculate_cost(params) : cost,
        params: params,
        metadata: metadata,
        executed_at: Time.current,
        gem_version: UsageCredits::VERSION
      }
    end

    private

    # =========================================
    # Parameter Handling
    # =========================================

    # Normalize different parameter formats
    # - Handles different size units (MB, bytes)
    # - Handles different parameter names
    def normalize_params(params)
      params = params.symbolize_keys

      # Handle different size specifications
      size = if params[:mb]
        normalize_quantity(params[:mb], :mb)
      elsif params[:kb]
        normalize_quantity(params[:kb], :kb) / 1024.0
      elsif params[:gb]
        normalize_quantity(params[:gb], :gb) * 1024.0
      elsif params[:size_mb]
        normalize_quantity(params[:size_mb], :size_mb)
      elsif params[:size_megabytes]
        normalize_quantity(params[:size_megabytes], :size_megabytes)
      elsif params[:size]
        normalize_quantity(params[:size], :size) / 1.megabyte
      else
        0.0
      end

      # Handle generic unit-based operations
      units = normalize_quantity(params[:units], :units) if params[:units]

      params.merge(
        size: (size * 1.megabyte).to_i,   # Raw bytes
        mb: size,                         # MB for convenience
        units: units || 0.0               # Generic units
      )
    end

    def normalize_quantity(value, name)
      number = Float(value)
      unless number.finite? && !number.negative?
        raise ArgumentError, "#{name} must be a finite, non-negative number"
      end

      number
    rescue ArgumentError, TypeError
      raise ArgumentError, "#{name} must be a finite, non-negative number"
    end
  end
end
