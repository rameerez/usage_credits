# frozen_string_literal: true

require "test_helper"

# ============================================================================
# CREDIT CALCULATOR TEST SUITE
# ============================================================================
#
# This test suite tests the CreditCalculator helper module which handles
# ALL money-to-credits conversions throughout the gem.
#
# This is BUSINESS-CRITICAL code that ensures correct credit calculations
# for purchases and usage tracking. Errors here directly affect revenue!
#
# The module provides:
#   - Configurable rounding strategies (ceil, floor, round)
#   - Money-to-credits conversion
#   - Credits-to-money conversion
#   - Consistent credit math across the entire gem
#
# ============================================================================

class CreditCalculatorTest < ActiveSupport::TestCase
  setup do
    UsageCredits.reset!
  end

  teardown do
    UsageCredits.reset!
  end

  # ========================================
  # ROUNDING STRATEGIES
  # ========================================

  test "apply_rounding with ceil strategy rounds up" do
    UsageCredits.configure do |config|
      config.rounding_strategy = :ceil
    end

    assert_equal 6, UsageCredits::CreditCalculator.apply_rounding(5.1)
    assert_equal 6, UsageCredits::CreditCalculator.apply_rounding(5.5)
    assert_equal 6, UsageCredits::CreditCalculator.apply_rounding(5.9)
  end

  test "apply_rounding with floor strategy rounds down" do
    UsageCredits.configure do |config|
      config.rounding_strategy = :floor
    end

    assert_equal 5, UsageCredits::CreditCalculator.apply_rounding(5.1)
    assert_equal 5, UsageCredits::CreditCalculator.apply_rounding(5.5)
    assert_equal 5, UsageCredits::CreditCalculator.apply_rounding(5.9)
  end

  test "apply_rounding with round strategy rounds to nearest" do
    UsageCredits.configure do |config|
      config.rounding_strategy = :round
    end

    assert_equal 5, UsageCredits::CreditCalculator.apply_rounding(5.1)
    assert_equal 5, UsageCredits::CreditCalculator.apply_rounding(5.4)
    assert_equal 6, UsageCredits::CreditCalculator.apply_rounding(5.5)
    assert_equal 6, UsageCredits::CreditCalculator.apply_rounding(5.9)
  end

  test "apply_rounding defaults to ceil when not configured" do
    # No configuration, should default to ceil
    assert_equal 6, UsageCredits::CreditCalculator.apply_rounding(5.1)
  end

  test "apply_rounding defaults to ceil for invalid strategy" do
    UsageCredits.configure do |config|
      config.rounding_strategy = :invalid_strategy
    end

    # Should fall back to ceil for safety (never undercharge)
    assert_equal 6, UsageCredits::CreditCalculator.apply_rounding(5.1)
  end

  test "apply_rounding handles whole numbers correctly" do
    UsageCredits.configure do |config|
      config.rounding_strategy = :ceil
    end

    assert_equal 5, UsageCredits::CreditCalculator.apply_rounding(5.0)
    assert_equal 100, UsageCredits::CreditCalculator.apply_rounding(100.0)
  end

  # ========================================
  # MONEY TO CREDITS CONVERSION
  # ========================================

  test "money_to_credits converts cents to credits with exchange rate" do
    UsageCredits.configure do |config|
      config.rounding_strategy = :ceil
    end

    # 100 cents ($1.00) at rate 10 = 10 credits
    assert_equal 10, UsageCredits::CreditCalculator.money_to_credits(100, 10)

    # 1000 cents ($10.00) at rate 100 = 1000 credits
    assert_equal 1000, UsageCredits::CreditCalculator.money_to_credits(1000, 100)
  end

  test "money_to_credits rounds up with ceil strategy" do
    UsageCredits.configure do |config|
      config.rounding_strategy = :ceil
    end

    # 333 cents at rate 10 should round up: 333 * 10 / 100 = 33.3 -> 34
    assert_equal 34, UsageCredits::CreditCalculator.money_to_credits(333, 10)
  end

  test "money_to_credits rounds down with floor strategy" do
    UsageCredits.configure do |config|
      config.rounding_strategy = :floor
    end

    # 333 cents at rate 10 should round down: 333 * 10 / 100 = 33.3 -> 33
    assert_equal 33, UsageCredits::CreditCalculator.money_to_credits(333, 10)
  end

  test "money_to_credits handles zero amount" do
    assert_equal 0, UsageCredits::CreditCalculator.money_to_credits(0, 10)
  end

  test "money_to_credits handles large amounts" do
    UsageCredits.configure do |config|
      config.rounding_strategy = :ceil
    end

    # 100,000 cents ($1000.00) at rate 1000 = 1,000,000 credits
    assert_equal 1_000_000, UsageCredits::CreditCalculator.money_to_credits(100_000, 1000)
  end

  # ========================================
  # CREDITS TO MONEY CONVERSION
  # ========================================

  test "credits_to_money converts credits to cents with exchange rate" do
    UsageCredits.configure do |config|
      config.rounding_strategy = :ceil
    end

    # 10 credits at rate 10 = 100 cents ($1.00)
    assert_equal 100, UsageCredits::CreditCalculator.credits_to_money(10, 10)

    # 1000 credits at rate 100 = 1000 cents ($10.00)
    assert_equal 1000, UsageCredits::CreditCalculator.credits_to_money(1000, 100)
  end

  test "credits_to_money rounds up with ceil strategy" do
    UsageCredits.configure do |config|
      config.rounding_strategy = :ceil
    end

    # 333 credits at rate 10: 333 * 100 / 10 = 3330.0 -> 3330
    # Let's use a fractional case: 5 credits at rate 12 = 5 * 100 / 12 = 41.666... -> 42
    assert_equal 42, UsageCredits::CreditCalculator.credits_to_money(5, 12)
  end

  test "credits_to_money rounds down with floor strategy" do
    UsageCredits.configure do |config|
      config.rounding_strategy = :floor
    end

    # 5 credits at rate 12 = 5 * 100 / 12 = 41.666... -> 41
    assert_equal 41, UsageCredits::CreditCalculator.credits_to_money(5, 12)
  end

  test "credits_to_money handles zero credits" do
    assert_equal 0, UsageCredits::CreditCalculator.credits_to_money(0, 10)
  end

  # ========================================
  # EDGE CASES & PRECISION
  # ========================================

  test "handles fractional exchange rates correctly" do
    UsageCredits.configure do |config|
      config.rounding_strategy = :ceil
    end

    # 100 cents at rate 0.5 = 100 * 0.5 / 100 = 0.5 -> 1 credit (ceil)
    assert_equal 1, UsageCredits::CreditCalculator.money_to_credits(100, 0.5)
  end

  test "ensures symmetric conversions are consistent" do
    UsageCredits.configure do |config|
      config.rounding_strategy = :round
    end

    # Convert money to credits
    credits = UsageCredits::CreditCalculator.money_to_credits(1000, 10)

    # Convert back to money
    money = UsageCredits::CreditCalculator.credits_to_money(credits, 10)

    # Should be close (may not be exact due to rounding)
    assert money >= 990 && money <= 1010
  end

  test "never undercharges with default ceil strategy" do
    # Default should be ceil to never undercharge customers

    # Fractional result should always round up
    result = UsageCredits::CreditCalculator.money_to_credits(333, 10)

    # 333 * 10 / 100 = 33.3, should round to 34 (not 33)
    assert result >= 34
  end

  # ========================================
  # ADDITIONAL EDGE CASES
  # ========================================

  test "handles very small exchange rates" do
    UsageCredits.configure do |config|
      config.rounding_strategy = :ceil
    end

    # 1000 cents at rate 0.01 = 1000 * 0.01 / 100 = 0.1 -> 1 credit
    assert_equal 1, UsageCredits::CreditCalculator.money_to_credits(1000, 0.01)
  end

  test "handles very large exchange rates" do
    UsageCredits.configure do |config|
      config.rounding_strategy = :ceil
    end

    # 100 cents at rate 10000 = 100 * 10000 / 100 = 10000 credits
    assert_equal 10000, UsageCredits::CreditCalculator.money_to_credits(100, 10000)
  end

  test "handles negative amounts gracefully" do
    UsageCredits.configure do |config|
      config.rounding_strategy = :ceil
    end

    # Negative amounts should still work mathematically
    # -100 * 10 / 100 = -10
    result = UsageCredits::CreditCalculator.money_to_credits(-100, 10)
    assert_equal(-10, result)
  end

  test "apply_rounding handles negative numbers" do
    UsageCredits.configure do |config|
      config.rounding_strategy = :ceil
    end

    # -5.3 should ceil to -5 (towards zero)
    assert_equal(-5, UsageCredits::CreditCalculator.apply_rounding(-5.3))
  end

  test "apply_rounding with floor handles negative numbers" do
    UsageCredits.configure do |config|
      config.rounding_strategy = :floor
    end

    # -5.3 should floor to -6 (away from zero)
    assert_equal(-6, UsageCredits::CreditCalculator.apply_rounding(-5.3))
  end

  test "consistent behavior across all strategies for exact values" do
    [5.0, 10.0, 100.0, 1000.0].each do |exact_value|
      [:ceil, :floor, :round].each do |strategy|
        UsageCredits.configure do |config|
          config.rounding_strategy = strategy
        end

        result = UsageCredits::CreditCalculator.apply_rounding(exact_value)
        assert_equal exact_value.to_i, result, "Strategy #{strategy} failed for #{exact_value}"
      end
    end
  end
end
