# frozen_string_literal: true

module UsageCredits
  # Configuration class for UsageCredits
  class Configuration
    # Default currency for credit pack pricing
    attr_accessor :default_currency

    # Default threshold for low balance alerts
    attr_reader :low_balance_threshold

    # Whether to allow negative balances (useful for enterprise customers)
    attr_accessor :allow_negative_balance

    # Customize credit rounding behavior
    attr_accessor :rounding_strategy

    def initialize
      @default_currency = :usd
      @low_balance_threshold = 100
      @allow_negative_balance = false
      @credit_formatter = ->(amount) { "#{amount} credits" }
      @rounding_strategy = :round
      @event_handlers = {}
      @credit_expiration = nil
    end

    # More intuitive low balance threshold setting
    def low_balance_threshold=(amount)
      @low_balance_threshold = amount.is_a?(UsageCredits::Amount) ? amount.to_i : amount
    end

    # More intuitive credit formatting
    def format_credits(&block)
      @credit_formatter = block
    end

    def credit_formatter
      @credit_formatter
    end

    # More intuitive event handling
    def on_low_balance(&block)
      @event_handlers[:low_balance] = block
    end

    def event_handler
      lambda do |event, data|
        case event
        when :low_balance_reached
          @event_handlers[:low_balance]&.call(data[:wallet].owner)
        else
          # Handle other events
        end
      end
    end

    # More intuitive credit expiration
    def expire_credits_after(duration)
      @credit_expiration = duration.is_a?(UsageCredits::TimeAmount) ? duration.to_i : duration
    end

    def credit_expiration_period
      @credit_expiration
    end

    # Validate configuration
    def validate!
      validate_currency!
      validate_threshold!
      validate_rounding_strategy!
      true
    end

    private

    def validate_currency!
      return if [:usd, :eur, :gbp].include?(@default_currency)

      raise ArgumentError, "Invalid currency: #{@default_currency}"
    end

    def validate_threshold!
      return if @low_balance_threshold.nil? ||
                (@low_balance_threshold.is_a?(Integer) && @low_balance_threshold.positive?)

      raise ArgumentError, "Invalid low balance threshold: #{@low_balance_threshold}"
    end

    def validate_rounding_strategy!
      return if [:round, :floor, :ceil].include?(@rounding_strategy)

      raise ArgumentError, "Invalid rounding strategy: #{@rounding_strategy}"
    end
  end
end
