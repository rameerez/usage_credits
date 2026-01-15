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

    # Minimum allowed fulfillment period for subscription plans.
    # Defaults to 1.day to prevent accidental 1-second refill loops in production.
    # Can be set to shorter periods (e.g., 2.seconds) in development/test for faster iteration.
    attr_reader :min_fulfillment_period

    # =========================================
    # Low balance
    # =========================================

    attr_accessor :allow_negative_balance

    attr_reader :low_balance_threshold

    attr_reader :low_balance_callback

    # =========================================
    # Lifecycle Callbacks
    # =========================================

    attr_reader :on_credits_added_callback,
                :on_credits_deducted_callback,
                :on_low_balance_reached_callback,
                :on_balance_depleted_callback,
                :on_insufficient_credits_callback,
                :on_subscription_credits_awarded_callback,
                :on_credit_pack_purchased_callback

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
      # long enough that there's a smooth transition and users never get zero credits in between fulfillment periods
      # A good setting is to match the frequency of your UsageCredits::FulfillmentJob runs
      @fulfillment_grace_period = 5.minutes # If you run your fulfillment job every 5 minutes, this should be enough

      # Minimum fulfillment period - prevents accidental 1-second refill loops in production
      @min_fulfillment_period = 1.day

      @allow_negative_balance = false
      @low_balance_threshold = nil
      @low_balance_callback = nil # Called when user hits low_balance_threshold

      # Lifecycle callbacks (all nil by default)
      @on_credits_added_callback = nil
      @on_credits_deducted_callback = nil
      @on_low_balance_reached_callback = nil
      @on_balance_depleted_callback = nil
      @on_insufficient_credits_callback = nil
      @on_subscription_credits_awarded_callback = nil
      @on_credit_pack_purchased_callback = nil
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

      # Warn if fulfillment period is shorter than grace period (grace will be auto-capped)
      warn_if_grace_period_exceeds_fulfillment(plan)

      @credit_subscription_plans[name] = plan
    end

    # Find a subscription plan by its processor-specific ID
    # Works with both single-price and multi-period plans
    # @param processor_id [String] The price ID to search for
    # @return [CreditSubscriptionPlan, nil] The matching plan or nil
    def find_subscription_plan_by_processor_id(processor_id)
      @credit_subscription_plans.values.find do |plan|
        plan.matches_processor_id?(processor_id)
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

    def min_fulfillment_period=(value)
      unless value.is_a?(ActiveSupport::Duration)
        raise ArgumentError, "Minimum fulfillment period must be an ActiveSupport::Duration (e.g. 1.day, 2.seconds)"
      end

      if value < 1.second
        raise ArgumentError, "Minimum fulfillment period must be at least 1 second"
      end

      @min_fulfillment_period = value
    end

    # =========================================
    # Callback & Formatter Configuration
    # =========================================

    # Set how credits are displayed in the UI
    def format_credits(&block)
      @credit_formatter = block
    end

    # =========================================
    # Lifecycle Callback DSL Methods
    # =========================================
    # All methods allow nil block to clear the callback (useful for testing)

    # Called after credits are added to a wallet
    def on_credits_added(&block)
      @on_credits_added_callback = block
    end

    # Called after credits are deducted from a wallet
    def on_credits_deducted(&block)
      @on_credits_deducted_callback = block
    end

    # Called when balance crosses below the low_balance_threshold
    # Receives CallbackContext with full event data
    def on_low_balance_reached(&block)
      @on_low_balance_reached_callback = block
    end

    # Called when balance reaches exactly zero
    def on_balance_depleted(&block)
      @on_balance_depleted_callback = block
    end

    # Called when an operation fails due to insufficient credits
    def on_insufficient_credits(&block)
      @on_insufficient_credits_callback = block
    end

    # Called after subscription credits are awarded
    def on_subscription_credits_awarded(&block)
      @on_subscription_credits_awarded_callback = block
    end

    # Called after a credit pack is purchased
    def on_credit_pack_purchased(&block)
      @on_credit_pack_purchased_callback = block
    end

    # BACKWARD COMPATIBILITY: Legacy method that receives owner, not context
    # Existing users' code: config.on_low_balance { |owner| ... }
    def on_low_balance(&block)
      raise ArgumentError, "Block is required for low balance callback" unless block_given?
      # Store legacy callback as before (for backward compat with direct calls)
      @low_balance_callback = block
      # Also create a wrapper for new callback system that extracts owner from context
      @on_low_balance_reached_callback = ->(ctx) { block.call(ctx.owner) }
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

    # Warn developers when grace period exceeds fulfillment period
    # In this case, the grace period will be automatically capped to the fulfillment period
    # to prevent balance accumulation (credits piling up because they don't expire fast enough)
    def warn_if_grace_period_exceeds_fulfillment(plan)
      return unless plan.fulfillment_period.present?
      return if plan.rollover_enabled  # Grace period only matters for expiring credits

      fulfillment_duration = plan.parsed_fulfillment_period

      if @fulfillment_grace_period > fulfillment_duration
        Rails.logger.warn(
          "[UsageCredits] Subscription plan '#{plan.name}' has a fulfillment period " \
          "(#{plan.fulfillment_period}) shorter than the configured grace period " \
          "(#{@fulfillment_grace_period.inspect}). The grace period will be automatically " \
          "capped to #{fulfillment_duration.inspect} for this plan to prevent balance accumulation. " \
          "Consider adjusting config.fulfillment_grace_period if this is not intended."
        )
      end
    end
  end
end
