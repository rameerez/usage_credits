# frozen_string_literal: true

module UsageCredits
  # Configuration for the UsageCredits gem. This is the single source of truth for all settings.
  # This is what turns what's defined in the initializer DSL into actual objects we can use and operate with.
  class Configuration
    VALID_ROUNDING_STRATEGIES = [:ceil, :floor, :round].freeze
    VALID_CURRENCIES = [:usd, :eur, :gbp, :sgd, :chf].freeze

    # =========================================
    # Core Data Stores
    # =========================================

    # Stores all the things users can do with credits
    attr_reader :operations

    # Stores all the things users can buy or subscribe to
    attr_reader :credit_packs
    attr_reader :credit_subscription_plans

    # =========================================
    # Basic Settings
    # =========================================

    attr_reader :default_currency

    attr_reader :rounding_strategy

    attr_reader :credit_formatter

    attr_reader :fulfillment_grace_period

    # =========================================
    # Low balance
    # =========================================

    attr_accessor :allow_negative_balance

    attr_reader :low_balance_threshold

    attr_reader :low_balance_callback

    def initialize
      # Initialize empty data stores
      @operations = {}                  # Credit-consuming operations (e.g., "send_email: 1 credit")
      @credit_packs = {}                # One-time purchases (e.g., "100 credits for $49")
      @credit_subscription_plans = {}   # Recurring plans (e.g., "1000 credits/month for $99")

      # Set sensible defaults
      @default_currency = :usd
      @rounding_strategy = :ceil  # Always round up to ensure we never undercharge
      @credit_formatter = ->(amount) { "#{amount} credits" }  # How to format credit amounts in the UI

      # Grace period for credit expiration after fulfillment period ends.
      # For how long will expiring credits "overlap" the following fulfillment period.
      # This ensures smooth transition between fulfillment periods.
      # For this amount of time, old, already expired credits will be erroneously counted as available in the user's balance.
      # Keep it short enough that users don't notice they have the last period's credits still available, but
      # long enough that there's a smooth transition and users never get zero credits in between fullfillment periods
      # A good setting is to match the frequency of your UsageCredits::FulfillmentJob runs
      @fulfillment_grace_period = 5.minutes # If you run your fulfillment job every 5 minutes, this should be enough

      @allow_negative_balance = false
      @low_balance_threshold = nil
      @low_balance_callback = nil # Called when user hits low_balance_threshold
    end

    # =========================================
    # DSL Methods for Defining Things
    # =========================================

    # Define a credit-consuming operation
    def operation(name, &block)
      raise ArgumentError, "Block is required for operation definition" unless block_given?
      operation = Operation.new(name)
      operation.instance_eval(&block)
      @operations[name.to_sym] = operation
      operation
    end

    # Define a one-time purchase credit pack
    def credit_pack(name, &block)
      raise ArgumentError, "Block is required for credit pack definition" unless block_given?
      raise ArgumentError, "Credit pack name can't be blank" if name.blank?

      name = name.to_sym
      pack = CreditPack.new(name)
      pack.instance_eval(&block)
      pack.validate!
      @credit_packs[name] = pack
    end

    # Define a recurring subscription plan
    def subscription_plan(name, &block)
      raise ArgumentError, "Block is required for subscription plan definition" unless block_given?
      raise ArgumentError, "Subscription plan name can't be blank" if name.blank?

      name = name.to_sym
      plan = CreditSubscriptionPlan.new(name)
      plan.instance_eval(&block)
      plan.validate!
      @credit_subscription_plans[name] = plan
    end

    # Find a subscription plan by its processor-specific ID
    def find_subscription_plan_by_processor_id(processor_id)
      @credit_subscription_plans.values.find do |plan|
        plan.processor_plan_ids.values.include?(processor_id)
      end
    end

    # =========================================
    # Configuration Setters
    # =========================================

    # Set default currency with validation
    def default_currency=(value)
      value = value.to_s.downcase.to_sym
      unless VALID_CURRENCIES.include?(value)
        raise ArgumentError, "Invalid currency. Must be one of: #{VALID_CURRENCIES.join(', ')}"
      end
      @default_currency = value
    end

    # Set low balance threshold with validation
    def low_balance_threshold=(value)
      if value
        value = value.to_i
        raise ArgumentError, "Low balance threshold must be greater than or equal to zero" if value.negative?
      end
      @low_balance_threshold = value
    end

    # Set rounding strategy with validation
    def rounding_strategy=(strategy)
      strategy = strategy.to_sym if strategy.respond_to?(:to_sym)
      unless VALID_ROUNDING_STRATEGIES.include?(strategy)
        strategy = :ceil  # Default to ceiling if invalid
      end
      @rounding_strategy = strategy
    end

    def fulfillment_grace_period=(value)
      if value.nil? || value&.to_i == 0
        @fulfillment_grace_period = 1.second
        return
      end

      unless value.is_a?(ActiveSupport::Duration)
        raise ArgumentError, "Fulfillment grace period must be an ActiveSupport::Duration (e.g. 1.day, 7.minutes)"
      end

      @fulfillment_grace_period = value
    end

    # =========================================
    # Callback & Formatter Configuration
    # =========================================

    # Set how credits are displayed in the UI
    def format_credits(&block)
      @credit_formatter = block
    end

    # Set what happens when credits are low
    def on_low_balance(&block)
      raise ArgumentError, "Block is required for low balance callback" unless block_given?
      @low_balance_callback = block
    end

    # =========================================
    # Validation
    # =========================================

    # Ensure configuration is valid
    def validate!
      validate_currency!
      validate_threshold!
      validate_rounding_strategy!
      true
    end

    private

    def validate_currency!
      raise ArgumentError, "Default currency can't be blank" if default_currency.blank?
      unless VALID_CURRENCIES.include?(default_currency.to_s.downcase.to_sym)
        raise ArgumentError, "Invalid currency. Must be one of: #{VALID_CURRENCIES.join(', ')}"
      end
    end

    def validate_threshold!
      if @low_balance_threshold && @low_balance_threshold.negative?
        raise ArgumentError, "Low balance threshold must be greater than or equal to zero"
      end
    end

    def validate_rounding_strategy!
      unless VALID_ROUNDING_STRATEGIES.include?(@rounding_strategy)
        raise ArgumentError, "Invalid rounding strategy. Must be one of: #{VALID_ROUNDING_STRATEGIES.join(', ')}"
      end
    end
  end
end
