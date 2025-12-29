# frozen_string_literal: true

require "test_helper"

# ============================================================================
# PERIOD PARSER TEST SUITE
# ============================================================================
#
# This test suite tests the PeriodParser module which handles parsing and
# normalization of time periods throughout the gem.
#
# The parser:
#   - Converts symbols like :monthly to ActiveSupport::Duration (1.month)
#   - Validates periods against the configured minimum
#   - Supports parsing period strings like "2.weeks" or "3 months"
#   - Enforces minimum period constraints from configuration
#
# ============================================================================

class UsageCredits::PeriodParserTest < ActiveSupport::TestCase
  setup do
    UsageCredits.reset!
  end

  teardown do
    UsageCredits.reset!
  end

  # ========================================
  # NORMALIZE PERIOD - BASIC FUNCTIONALITY
  # ========================================

  test "normalize_period converts :daily to 1.day" do
    assert_equal 1.day, UsageCredits::PeriodParser.normalize_period(:daily)
  end

  test "normalize_period converts :day to 1.day" do
    assert_equal 1.day, UsageCredits::PeriodParser.normalize_period(:day)
  end

  test "normalize_period converts :weekly to 1.week" do
    assert_equal 1.week, UsageCredits::PeriodParser.normalize_period(:weekly)
  end

  test "normalize_period converts :week to 1.week" do
    assert_equal 1.week, UsageCredits::PeriodParser.normalize_period(:week)
  end

  test "normalize_period converts :monthly to 1.month" do
    assert_equal 1.month, UsageCredits::PeriodParser.normalize_period(:monthly)
  end

  test "normalize_period converts :month to 1.month" do
    assert_equal 1.month, UsageCredits::PeriodParser.normalize_period(:month)
  end

  test "normalize_period converts :quarterly to 3.months" do
    assert_equal 3.months, UsageCredits::PeriodParser.normalize_period(:quarterly)
  end

  test "normalize_period converts :quarter to 3.months" do
    assert_equal 3.months, UsageCredits::PeriodParser.normalize_period(:quarter)
  end

  test "normalize_period converts :yearly to 1.year" do
    assert_equal 1.year, UsageCredits::PeriodParser.normalize_period(:yearly)
  end

  test "normalize_period converts :year to 1.year" do
    assert_equal 1.year, UsageCredits::PeriodParser.normalize_period(:year)
  end

  test "normalize_period converts :annually to 1.year" do
    assert_equal 1.year, UsageCredits::PeriodParser.normalize_period(:annually)
  end

  # ========================================
  # NORMALIZE PERIOD - NEW TIME UNITS
  # ========================================

  test "normalize_period converts :second to 1.second when min period allows" do
    UsageCredits.configuration.min_fulfillment_period = 1.second

    assert_equal 1.second, UsageCredits::PeriodParser.normalize_period(:second)
  end

  test "normalize_period converts :seconds to 1.second when min period allows" do
    UsageCredits.configuration.min_fulfillment_period = 1.second

    assert_equal 1.second, UsageCredits::PeriodParser.normalize_period(:seconds)
  end

  test "normalize_period converts :minute to 1.minute when min period allows" do
    UsageCredits.configuration.min_fulfillment_period = 1.second

    assert_equal 1.minute, UsageCredits::PeriodParser.normalize_period(:minute)
  end

  test "normalize_period converts :minutes to 1.minute when min period allows" do
    UsageCredits.configuration.min_fulfillment_period = 1.second

    assert_equal 1.minute, UsageCredits::PeriodParser.normalize_period(:minutes)
  end

  test "normalize_period converts :hour to 1.hour when min period allows" do
    UsageCredits.configuration.min_fulfillment_period = 1.second

    assert_equal 1.hour, UsageCredits::PeriodParser.normalize_period(:hour)
  end

  test "normalize_period converts :hours to 1.hour when min period allows" do
    UsageCredits.configuration.min_fulfillment_period = 1.second

    assert_equal 1.hour, UsageCredits::PeriodParser.normalize_period(:hours)
  end

  test "normalize_period converts :hourly to 1.hour when min period allows" do
    UsageCredits.configuration.min_fulfillment_period = 1.second

    assert_equal 1.hour, UsageCredits::PeriodParser.normalize_period(:hourly)
  end

  # ========================================
  # NORMALIZE PERIOD - DURATION OBJECTS
  # ========================================

  test "normalize_period accepts ActiveSupport::Duration directly" do
    duration = 2.weeks
    assert_equal duration, UsageCredits::PeriodParser.normalize_period(duration)
  end

  test "normalize_period accepts custom duration like 14.days" do
    assert_equal 14.days, UsageCredits::PeriodParser.normalize_period(14.days)
  end

  test "normalize_period accepts complex duration like 3.months" do
    assert_equal 3.months, UsageCredits::PeriodParser.normalize_period(3.months)
  end

  # ========================================
  # NORMALIZE PERIOD - VALIDATION
  # ========================================

  test "normalize_period raises for unsupported symbol" do
    error = assert_raises(ArgumentError) do
      UsageCredits::PeriodParser.normalize_period(:biweekly)
    end

    assert_includes error.message, "Unsupported period"
  end

  test "normalize_period returns nil for nil input" do
    assert_nil UsageCredits::PeriodParser.normalize_period(nil)
  end

  test "normalize_period enforces minimum period with default config (1.day)" do
    # Default minimum is 1.day
    error = assert_raises(ArgumentError) do
      UsageCredits::PeriodParser.normalize_period(12.hours)
    end

    assert_includes error.message, "Period must be at least"
  end

  test "normalize_period enforces minimum period for symbols" do
    # Default minimum is 1.day, so :hour should fail
    error = assert_raises(ArgumentError) do
      UsageCredits::PeriodParser.normalize_period(:hour)
    end

    assert_includes error.message, "Period must be at least"
  end

  test "normalize_period allows periods meeting minimum threshold" do
    # Default minimum is 1.day
    assert_equal 1.week, UsageCredits::PeriodParser.normalize_period(1.week)
    assert_equal 1.month, UsageCredits::PeriodParser.normalize_period(1.month)
  end

  # ========================================
  # PARSE PERIOD - STRING PARSING
  # ========================================

  test "parse_period parses '1.month' string" do
    result = UsageCredits::PeriodParser.parse_period("1.month")
    assert_equal 1.month, result
  end

  test "parse_period parses '2 weeks' string" do
    result = UsageCredits::PeriodParser.parse_period("2 weeks")
    assert_equal 2.weeks, result
  end

  test "parse_period parses '3.days' string" do
    result = UsageCredits::PeriodParser.parse_period("3.days")
    assert_equal 3.days, result
  end

  test "parse_period parses '12 months' string" do
    result = UsageCredits::PeriodParser.parse_period("12 months")
    assert_equal 12.months, result
  end

  test "parse_period accepts ActiveSupport::Duration directly" do
    duration = 1.month
    assert_equal duration, UsageCredits::PeriodParser.parse_period(duration)
  end

  test "parse_period raises for invalid format" do
    error = assert_raises(ArgumentError) do
      UsageCredits::PeriodParser.parse_period("invalid")
    end

    assert_includes error.message, "Invalid period format"
  end

  test "parse_period raises for unsupported unit" do
    error = assert_raises(ArgumentError) do
      UsageCredits::PeriodParser.parse_period("1.fortnight")
    end

    assert_includes error.message, "Unsupported period unit"
  end

  test "parse_period enforces minimum period" do
    # Default minimum is 1.day
    error = assert_raises(ArgumentError) do
      UsageCredits::PeriodParser.parse_period("6.hours")
    end

    assert_includes error.message, "Period must be at least"
  end

  test "parse_period with new time units when configured" do
    UsageCredits.configuration.min_fulfillment_period = 1.second

    assert_equal 2.seconds, UsageCredits::PeriodParser.parse_period("2.seconds")
    assert_equal 5.minutes, UsageCredits::PeriodParser.parse_period("5.minutes")
    assert_equal 3.hours, UsageCredits::PeriodParser.parse_period("3.hours")
  end

  test "parse_period handles alias units correctly without NoMethodError" do
    UsageCredits.configuration.min_fulfillment_period = 1.second

    # :hourly is an alias that doesn't have a direct ActiveSupport method
    # It should map to :hour internally
    assert_equal 1.hour, UsageCredits::PeriodParser.parse_period("1.hourly")
    assert_equal 2.hours, UsageCredits::PeriodParser.parse_period("2.hourly")
  end

  test "canonical_unit_for maps aliases to canonical units" do
    assert_equal :second, UsageCredits::PeriodParser.canonical_unit_for(:second)
    assert_equal :second, UsageCredits::PeriodParser.canonical_unit_for(:seconds)

    assert_equal :minute, UsageCredits::PeriodParser.canonical_unit_for(:minute)
    assert_equal :minute, UsageCredits::PeriodParser.canonical_unit_for(:minutes)

    assert_equal :hour, UsageCredits::PeriodParser.canonical_unit_for(:hour)
    assert_equal :hour, UsageCredits::PeriodParser.canonical_unit_for(:hours)
    assert_equal :hour, UsageCredits::PeriodParser.canonical_unit_for(:hourly)

    assert_equal :day, UsageCredits::PeriodParser.canonical_unit_for(:day)
    assert_equal :day, UsageCredits::PeriodParser.canonical_unit_for(:daily)

    assert_equal :week, UsageCredits::PeriodParser.canonical_unit_for(:week)
    assert_equal :week, UsageCredits::PeriodParser.canonical_unit_for(:weekly)

    assert_equal :month, UsageCredits::PeriodParser.canonical_unit_for(:month)
    assert_equal :month, UsageCredits::PeriodParser.canonical_unit_for(:monthly)

    assert_equal :quarter, UsageCredits::PeriodParser.canonical_unit_for(:quarter)
    assert_equal :quarter, UsageCredits::PeriodParser.canonical_unit_for(:quarterly)

    assert_equal :year, UsageCredits::PeriodParser.canonical_unit_for(:year)
    assert_equal :year, UsageCredits::PeriodParser.canonical_unit_for(:yearly)
    assert_equal :year, UsageCredits::PeriodParser.canonical_unit_for(:annually)
  end

  # ========================================
  # VALID PERIOD FORMAT
  # ========================================

  test "valid_period_format? returns true for valid period" do
    assert UsageCredits::PeriodParser.valid_period_format?("1.month")
  end

  test "valid_period_format? returns false for invalid period" do
    refute UsageCredits::PeriodParser.valid_period_format?("invalid")
  end

  test "valid_period_format? returns false for period below minimum" do
    # Default minimum is 1.day
    refute UsageCredits::PeriodParser.valid_period_format?("1.hour")
  end

  test "valid_period_format? returns true when period meets minimum" do
    UsageCredits.configuration.min_fulfillment_period = 1.second
    assert UsageCredits::PeriodParser.valid_period_format?("1.hour")
  end

  # ========================================
  # CONFIGURATION INTEGRATION
  # ========================================

  test "respects custom min_fulfillment_period configuration" do
    UsageCredits.configuration.min_fulfillment_period = 2.seconds

    # 2.seconds should be accepted (meets minimum)
    assert_equal 2.seconds, UsageCredits::PeriodParser.normalize_period(2.seconds)

    # 1.second should be rejected (below minimum)
    error = assert_raises(ArgumentError) do
      UsageCredits::PeriodParser.normalize_period(1.second)
    end

    assert_includes error.message, "Period must be at least"
  end

  test "allows very short periods in development mode simulation" do
    # Simulate development mode with 2.seconds minimum
    UsageCredits.configuration.min_fulfillment_period = 2.seconds

    # Should now accept 2.seconds duration
    assert_equal 2.seconds, UsageCredits::PeriodParser.normalize_period(2.seconds)
    assert_equal 2.seconds, UsageCredits::PeriodParser.parse_period("2.seconds")

    # Should accept 1.minute (which is greater than 2.seconds)
    assert_equal 1.minute, UsageCredits::PeriodParser.normalize_period(:minute)

    # Should accept 1.hour (which is greater than 2.seconds)
    assert_equal 1.hour, UsageCredits::PeriodParser.normalize_period(:hour)
  end

  test "production default prevents accidental fast refill loops" do
    # Default configuration (1.day minimum) should prevent fast refills
    assert_equal 1.day, UsageCredits.configuration.min_fulfillment_period

    # Should reject periods shorter than 1.day
    error = assert_raises(ArgumentError) do
      UsageCredits::PeriodParser.normalize_period(:hour)
    end

    assert_includes error.message, "Period must be at least 1 day"
  end

  # ========================================
  # EDGE CASES
  # ========================================

  test "handles very large period values" do
    large_period = 100.years
    assert_equal large_period, UsageCredits::PeriodParser.normalize_period(large_period)
  end

  test "parse_period handles large numeric values" do
    UsageCredits.configuration.min_fulfillment_period = 1.second
    result = UsageCredits::PeriodParser.parse_period("365.days")
    assert_equal 365.days, result
  end

  test "normalize_period is case-sensitive for symbols" do
    # Lowercase should work
    assert_equal 1.month, UsageCredits::PeriodParser.normalize_period(:month)

    # Uppercase should fail
    error = assert_raises(ArgumentError) do
      UsageCredits::PeriodParser.normalize_period(:MONTH)
    end

    assert_includes error.message, "Unsupported period"
  end
end
