# frozen_string_literal: true

module UsageCredits
  # Handles parsing and normalization of time periods throughout the gem.
  # Converts strings like "1.month" or symbols like :monthly into ActiveSupport::Duration objects.
  module PeriodParser

    # Canonical periods and their aliases
    VALID_PERIODS = {
      second: [:second, :seconds],        # 1.second
      minute: [:minute, :minutes],        # 1.minute
      hour: [:hour, :hours, :hourly],     # 1.hour
      day: [:day, :daily],                # 1.day
      week: [:week, :weekly],             # 1.week
      month: [:month, :monthly],          # 1.month
      quarter: [:quarter, :quarterly],    # 3.months
      year: [:year, :yearly, :annually]   # 1.year
    }.freeze

    MIN_PERIOD = 1.day  # Deprecated: Use UsageCredits.configuration.min_fulfillment_period instead

    module_function

    # Get the configured minimum fulfillment period
    def min_fulfillment_period
      # Use configured value if available, otherwise fall back to default
      if defined?(UsageCredits) && UsageCredits.respond_to?(:configuration)
        UsageCredits.configuration.min_fulfillment_period
      else
        MIN_PERIOD
      end
    end

    # Turns things like `:monthly` into `1.month` to always store consistent time periods
    def normalize_period(period)
      return nil unless period

      # Handle ActiveSupport::Duration objects directly
      if period.is_a?(ActiveSupport::Duration)
        min_period = min_fulfillment_period
        raise ArgumentError, "Period must be at least #{min_period.inspect}" if period < min_period
        period
      else
        # Convert symbols to canonical durations
        duration = case period
        when *VALID_PERIODS[:second] then 1.second
        when *VALID_PERIODS[:minute] then 1.minute
        when *VALID_PERIODS[:hour] then 1.hour
        when *VALID_PERIODS[:day] then 1.day
        when *VALID_PERIODS[:week] then 1.week
        when *VALID_PERIODS[:month] then 1.month
        when *VALID_PERIODS[:quarter] then 3.months
        when *VALID_PERIODS[:year] then 1.year
        else
          raise ArgumentError, "Unsupported period: #{period}. Supported periods: #{VALID_PERIODS.values.flatten.inspect}"
        end

        min_period = min_fulfillment_period
        raise ArgumentError, "Period must be at least #{min_period.inspect}" if duration < min_period
        duration
      end
    end

    # Parse a period string into an ActiveSupport::Duration
    # @param period_str [String, ActiveSupport::Duration] A string like "1.month" or "1 month" or an existing duration
    # @return [ActiveSupport::Duration] The parsed duration
    # @raise [ArgumentError] If the period string is invalid
    def parse_period(period_str)
      return period_str if period_str.is_a?(ActiveSupport::Duration)

      if period_str.to_s =~ /\A(\d+)[.\s](\w+)\z/
        amount = $1.to_i
        unit = $2.singularize.to_sym

        # Validate the unit is supported
        valid_units = VALID_PERIODS.values.flatten
        unless valid_units.include?(unit)
          raise ArgumentError, "Unsupported period unit: #{unit}. Supported units: #{valid_units.inspect}"
        end

        # Map alias to canonical unit (e.g., :hourly -> :hour, :seconds -> :second)
        canonical_unit = canonical_unit_for(unit)

        duration = amount.send(canonical_unit)
        min_period = min_fulfillment_period
        raise ArgumentError, "Period must be at least #{min_period.inspect}" if duration < min_period
        duration
      else
        raise ArgumentError, "Invalid period format: #{period_str}. Expected format: '1.month', '2 months', etc."
      end
    end

    # Map any alias to its canonical unit method name
    # @param unit [Symbol] The unit symbol (e.g., :hourly, :seconds, :day)
    # @return [Symbol] The canonical unit method (e.g., :hour, :second, :day)
    def canonical_unit_for(unit)
      # Find which canonical unit this alias belongs to
      VALID_PERIODS.each do |canonical, aliases|
        return canonical if aliases.include?(unit)
      end

      # Fallback to the unit itself if not found (shouldn't happen if validation passed)
      unit
    end

    # Validates that a period string matches the expected format and units
    def valid_period_format?(period_str)
      parse_period(period_str)
      true
    rescue ArgumentError
      false
    end

  end
end
