# frozen_string_literal: true

module UsageCredits
  # Handles parsing and normalization of time periods throughout the gem.
  # Converts strings like "1.month" or symbols like :monthly into ActiveSupport::Duration objects.
  module PeriodParser

    # Canonical periods and their aliases
    VALID_PERIODS = {
      day: [:day, :daily],                # 1.day
      week: [:week, :weekly],             # 1.week
      month: [:month, :monthly],          # 1.month
      quarter: [:quarter, :quarterly],    # 3.months
      year: [:year, :yearly, :annually]   # 1.year
    }.freeze

    MIN_PERIOD = 1.day

    module_function

    # Turns things like `:monthly` into `1.month` to always store consistent time periods
    def normalize_period(period)
      return nil unless period

      # Handle ActiveSupport::Duration objects directly
      if period.is_a?(ActiveSupport::Duration)
        raise ArgumentError, "Period must be at least #{MIN_PERIOD.inspect}" if period < MIN_PERIOD
        period
      else
        # Convert symbols to canonical durations
        case period
        when *VALID_PERIODS[:day] then 1.day
        when *VALID_PERIODS[:week] then 1.week
        when *VALID_PERIODS[:month] then 1.month
        when *VALID_PERIODS[:quarter] then 3.months
        when *VALID_PERIODS[:year] then 1.year
        else
          raise ArgumentError, "Unsupported period: #{period}. Supported periods: #{VALID_PERIODS.values.flatten.inspect}"
        end
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

        duration = amount.send(unit)
        raise ArgumentError, "Period must be at least #{MIN_PERIOD.inspect}" if duration < MIN_PERIOD
        duration
      else
        raise ArgumentError, "Invalid period format: #{period_str}. Expected format: '1.month', '2 months', etc."
      end
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
