# frozen_string_literal: true

require "test_helper"

class UsageCredits::OperationTest < ActiveSupport::TestCase
  setup do
    UsageCredits.reset!
  end

  teardown do
    UsageCredits.reset!
  end

  # ========================================
  # BASIC CREATION
  # ========================================

  test "creates operation with name" do
    operation = UsageCredits::Operation.new(:test_operation)
    assert_equal :test_operation, operation.name
  end

  test "creates operation with block configuration" do
    operation = UsageCredits::Operation.new(:test_operation) do
      costs 10.credits
    end

    assert_equal 10, operation.calculate_cost
  end

  test "default cost is zero (free)" do
    operation = UsageCredits::Operation.new(:free_operation)
    assert_equal 0, operation.calculate_cost
  end

  # ========================================
  # COST CALCULATION - FIXED
  # ========================================

  test "calculates fixed cost" do
    operation = UsageCredits::Operation.new(:fixed_op) do
      costs 25.credits
    end

    assert_equal 25, operation.calculate_cost
  end

  test "calculates fixed cost with alias" do
    operation = UsageCredits::Operation.new(:fixed_op) do
      cost 15.credits
    end

    assert_equal 15, operation.calculate_cost
  end

  test "calculates cost with Cost::Fixed object" do
    operation = UsageCredits::Operation.new(:fixed_op) do
      costs UsageCredits::Cost::Fixed.new(50)
    end

    assert_equal 50, operation.calculate_cost
  end

  # ========================================
  # COST CALCULATION - VARIABLE
  # ========================================

  test "calculates variable cost per MB" do
    operation = UsageCredits::Operation.new(:process_file) do
      costs 2.credits_per(:mb)
    end

    assert_equal 20, operation.calculate_cost(mb: 10)
  end

  test "calculates variable cost with size in bytes" do
    operation = UsageCredits::Operation.new(:process_file) do
      costs 1.credit_per(:mb)
    end

    # 5 MB in bytes
    assert_equal 5, operation.calculate_cost(size: 5.megabytes)
  end

  test "calculates variable cost per unit" do
    operation = UsageCredits::Operation.new(:send_emails) do
      costs 1.credit_per(:units)
    end

    assert_equal 100, operation.calculate_cost(units: 100)
  end

  test "variable cost with zero units returns zero" do
    operation = UsageCredits::Operation.new(:send_emails) do
      costs 5.credits_per(:units)
    end

    assert_equal 0, operation.calculate_cost(units: 0)
  end

  # ========================================
  # COST CALCULATION - COMPOUND
  # ========================================

  test "calculates compound cost (base + variable)" do
    operation = UsageCredits::Operation.new(:process_video) do
      costs 10.credits + 1.credit_per(:mb)
    end

    # 10 base + 5 MB * 1 = 15
    assert_equal 15, operation.calculate_cost(mb: 5)
  end

  test "calculates compound cost with multiple variable components" do
    operation = UsageCredits::Operation.new(:complex_op) do
      costs 5.credits + 2.credits_per(:mb)
    end

    # 5 base + 10 MB * 2 = 25
    assert_equal 25, operation.calculate_cost(mb: 10)
  end

  # ========================================
  # COST CALCULATION - LAMBDA
  # ========================================

  test "calculates cost with lambda" do
    operation = UsageCredits::Operation.new(:dynamic_op) do
      costs ->(params) { params[:multiplier] * 10 }
    end

    assert_equal 50, operation.calculate_cost(multiplier: 5)
  end

  test "lambda with invalid return value raises error" do
    operation = UsageCredits::Operation.new(:invalid_lambda) do
      costs ->(params) { 10.5 }  # Decimals not allowed
    end

    assert_raises(ArgumentError) do
      operation.calculate_cost
    end
  end

  test "lambda with negative return value raises error" do
    operation = UsageCredits::Operation.new(:negative_lambda) do
      costs ->(params) { -10 }
    end

    assert_raises(ArgumentError) do
      operation.calculate_cost
    end
  end

  # ========================================
  # VALIDATIONS
  # ========================================

  test "validates with custom condition" do
    operation = UsageCredits::Operation.new(:validated_op) do
      costs 10.credits
      validate ->(params) { params[:size_mb] <= 100 }, "File too large (max 100MB)"
    end

    # Should pass validation
    assert_nothing_raised do
      operation.validate!(size_mb: 50)
    end
  end

  test "raises InvalidOperation when validation fails" do
    operation = UsageCredits::Operation.new(:validated_op) do
      costs 10.credits
      validate ->(params) { params[:size_mb] <= 100 }, "File too large (max 100MB)"
    end

    error = assert_raises(UsageCredits::InvalidOperation) do
      operation.validate!(size_mb: 150)
    end

    assert_includes error.message, "File too large"
  end

  test "multiple validations all run" do
    operation = UsageCredits::Operation.new(:multi_validated) do
      costs 10.credits
      validate ->(params) { params[:size_mb] <= 100 }, "File too large"
      validate ->(params) { params[:size_mb] >= 1 }, "File too small"
    end

    assert_nothing_raised do
      operation.validate!(size_mb: 50)
    end

    assert_raises(UsageCredits::InvalidOperation) do
      operation.validate!(size_mb: 0)
    end
  end

  test "validation with default error message" do
    operation = UsageCredits::Operation.new(:default_message) do
      costs 10.credits
      validate ->(params) { false }  # Always fails
    end

    error = assert_raises(UsageCredits::InvalidOperation) do
      operation.validate!
    end

    assert_includes error.message, "Operation validation failed"
  end

  test "validation error in lambda is wrapped" do
    operation = UsageCredits::Operation.new(:error_in_validation) do
      costs 10.credits
      validate ->(params) { raise "Something broke!" }
    end

    error = assert_raises(UsageCredits::InvalidOperation) do
      operation.validate!
    end

    assert_includes error.message, "Validation error"
  end

  # ========================================
  # METADATA
  # ========================================

  test "stores custom metadata" do
    operation = UsageCredits::Operation.new(:with_metadata) do
      costs 10.credits
      meta(tier: "premium", feature: "video_processing")
    end

    assert_equal "premium", operation.metadata["tier"]
    assert_equal "video_processing", operation.metadata["feature"]
  end

  test "metadata keys are converted to strings" do
    operation = UsageCredits::Operation.new(:with_metadata) do
      meta(symbol_key: "value")
    end

    assert_equal "value", operation.metadata["symbol_key"]
  end

  test "multiple meta calls merge metadata" do
    operation = UsageCredits::Operation.new(:merged_metadata) do
      meta(key1: "value1")
      meta(key2: "value2")
    end

    assert_equal "value1", operation.metadata["key1"]
    assert_equal "value2", operation.metadata["key2"]
  end

  # ========================================
  # PARAMETER NORMALIZATION
  # ========================================

  test "normalizes size_mb parameter to mb" do
    operation = UsageCredits::Operation.new(:normalize_test) do
      costs 1.credit_per(:mb)
    end

    assert_equal 5, operation.calculate_cost(size_mb: 5)
  end

  test "normalizes size_megabytes parameter to mb" do
    operation = UsageCredits::Operation.new(:normalize_test) do
      costs 1.credit_per(:mb)
    end

    assert_equal 5, operation.calculate_cost(size_megabytes: 5)
  end

  test "normalizes bytes size to mb" do
    operation = UsageCredits::Operation.new(:normalize_test) do
      costs 1.credit_per(:mb)
    end

    # 10 MB in bytes
    assert_equal 10, operation.calculate_cost(size: 10.megabytes)
  end

  # ========================================
  # AUDIT TRAIL
  # ========================================

  test "generates audit hash with operation details" do
    operation = UsageCredits::Operation.new(:audited_op) do
      costs 25.credits
      meta(category: "processing")
    end

    audit = operation.to_audit_hash(file_id: 123)

    assert_equal :audited_op, audit[:operation]
    assert_equal 25, audit[:cost]
    assert_equal({ file_id: 123 }, audit[:params])
    assert_equal "processing", audit[:metadata]["category"]
    assert_not_nil audit[:executed_at]
    assert_equal UsageCredits::VERSION, audit[:gem_version]
  end

  # ========================================
  # ROUNDING STRATEGY
  # ========================================

  test "applies configured rounding strategy" do
    UsageCredits.configure do |config|
      config.rounding_strategy = :ceil
    end

    operation = UsageCredits::Operation.new(:rounding_test) do
      costs 1.credit_per(:mb)
    end

    # 2.5 MB should round up to 3
    assert_equal 3, operation.calculate_cost(mb: 2.5)
  end

  test "floor rounding strategy rounds down" do
    UsageCredits.configure do |config|
      config.rounding_strategy = :floor
    end

    operation = UsageCredits::Operation.new(:floor_test) do
      costs 1.credit_per(:mb)
    end

    # 2.9 MB should round down to 2
    assert_equal 2, operation.calculate_cost(mb: 2.9)
  end

  test "round rounding strategy uses standard rounding" do
    UsageCredits.configure do |config|
      config.rounding_strategy = :round
    end

    operation = UsageCredits::Operation.new(:round_test) do
      costs 1.credit_per(:mb)
    end

    # 2.4 MB should round to 2
    assert_equal 2, operation.calculate_cost(mb: 2.4)
    # 2.6 MB should round to 3
    assert_equal 3, operation.calculate_cost(mb: 2.6)
  end

  # ========================================
  # EDGE CASES
  # ========================================

  test "handles empty params" do
    operation = UsageCredits::Operation.new(:empty_params) do
      costs 10.credits
    end

    assert_equal 10, operation.calculate_cost({})
  end

  test "handles nil-equivalent params gracefully" do
    operation = UsageCredits::Operation.new(:nil_params) do
      costs 1.credit_per(:mb)
    end

    assert_equal 0, operation.calculate_cost({})
  end

  test "handles very large cost calculations" do
    operation = UsageCredits::Operation.new(:large_cost) do
      costs 1_000_000.credits
    end

    assert_equal 1_000_000, operation.calculate_cost
  end

  test "validation runs before cost calculation" do
    operation = UsageCredits::Operation.new(:validation_first) do
      costs ->(params) { params[:required_param] * 10 }
      validate ->(params) { params[:required_param].present? }, "required_param is required"
    end

    assert_raises(UsageCredits::InvalidOperation) do
      operation.calculate_cost({})
    end
  end
end
