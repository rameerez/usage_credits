# frozen_string_literal: true

module UsageCredits
  # A DSL to define subscription plans that give credits to users on a recurring basis.
  #
  # The actual credit fulfillment is handled by the PaySubscriptionExtension,
  # which monitors subscription events (creation, renewal, etc) and adds
  # credits to the user's wallet accordingly.
  #
  # @see PaySubscriptionExtension for the actual credit fulfillment logic
  class CreditSubscriptionPlan
    attr_reader :name,
                :processor_plan_ids,
                :fulfillment_period, :credits_per_period,
                :signup_bonus_credits, :trial_credits,
                :rollover_enabled,
                :expire_credits_on_cancel, :credit_expiration_period,
                :metadata

    attr_writer :fulfillment_period

    MIN_PERIOD = 1.day  # Deprecated: Use UsageCredits.configuration.min_fulfillment_period instead

    def initialize(name)
      @name = name
      @processor_plan_ids = {}  # Store processor-specific plan IDs
      @fulfillment_period = nil
      @credits_per_period = 0
      @signup_bonus_credits = 0
      @trial_credits = 0
      @rollover_enabled = false
      @expire_credits_on_cancel = false
      @credit_expiration_period = nil
      @metadata = {}
    end

    # =========================================
    # DSL Methods (used in initializer blocks)
    # =========================================

    # Set base credits given each period
    def gives(amount)
      if amount.is_a?(UsageCredits::Cost::Fixed)
        @credits_per_period = amount.amount
        @fulfillment_period = UsageCredits::PeriodParser.normalize_period(amount.period || 1.month)
        self
      else
        @credits_per_period = amount.to_i
        CreditGiver.new(self)
      end
    end

    # One-time signup bonus credits
    def signup_bonus(amount)
      @signup_bonus_credits = amount.to_i
    end

    # Credits given during trial period
    def trial_includes(amount)
      @trial_credits = amount.to_i
    end

    # Configure whether unused credits roll over between periods
    def unused_credits(behavior)
      @rollover_enabled = (behavior == :rollover)
    end

    # Configure credit expiration after subscription cancellation
    #
    # When a subscription is cancelled, you can control what happens to remaining credits:
    # 1. By default (if this is not called), users keep their credits forever
    # 2. If called with a duration, credits expire after that grace period
    # 3. If called with nil/0, credits expire immediately on cancellation
    #
    # @param duration [ActiveSupport::Duration, nil] Grace period before credits expire
    # @return [void]
    def expire_after(duration)
      @expire_credits_on_cancel = true
      @credit_expiration_period = duration
    end

    # Add custom metadata
    def meta(hash)
      @metadata.merge!(hash)
    end

    # =========================================
    # Payment Processor Integration
    # =========================================

    # Set the processor-specific plan ID(s)
    # Accepts either a single ID (String) or multiple period-specific IDs (Hash)
    #
    # @param processor [Symbol] The payment processor (e.g., :stripe)
    # @param id [String, Hash] Single ID or hash of period => ID pairs
    # @example Single ID (backward compatible)
    #   processor_plan(:stripe, "price_123")
    # @example Multiple periods
    #   processor_plan(:stripe, { month: "price_m", year: "price_y" })
    def processor_plan(processor, id)
      processor_plan_ids[processor.to_sym] = id
    end

    # Get the plan ID(s) for a specific processor
    # @param processor [Symbol] The payment processor
    # @param period [Symbol, nil] Optional specific period to retrieve
    # @return [String, Hash, nil] Single ID, hash of IDs, or nil
    def plan_id_for(processor, period: nil)
      ids = processor_plan_ids[processor.to_sym]

      # If no period specified, return as-is (String or Hash)
      return ids if period.nil?

      # If ids is a Hash, return the specific period
      return ids[period.to_sym] if ids.is_a?(Hash)

      # If ids is a String and they asked for a period, return nil (not multi-period)
      nil
    end

    # Shorthand for Stripe price ID(s)
    # Supports both single price and multi-period prices
    #
    # @overload stripe_price
    #   Get all Stripe price IDs
    #   @return [String, Hash] Single price ID or hash of period => price_id
    # @overload stripe_price(id)
    #   Set a single Stripe price ID (backward compatible)
    #   @param id [String] The Stripe price ID
    # @overload stripe_price(prices)
    #   Set multiple period-specific Stripe price IDs
    #   @param prices [Hash] Hash of period => price_id (e.g., { month: "price_m", year: "price_y" })
    # @overload stripe_price(period)
    #   Get Stripe price ID for a specific period
    #   @param period [Symbol] The billing period (e.g., :month, :year)
    #   @return [String, nil] Price ID for that period
    #
    # @example Get all prices
    #   plan.stripe_price # => { month: "price_m", year: "price_y" }
    # @example Get specific period
    #   plan.stripe_price(:month) # => "price_m"
    # @example Set single price (backward compatible)
    #   stripe_price "price_123"
    # @example Set multiple periods
    #   stripe_price month: "price_m", year: "price_y"
    def stripe_price(id_or_period = nil)
      if id_or_period.nil?
        # Getter: return all prices
        plan_id_for(:stripe)
      elsif id_or_period.is_a?(Hash)
        # Setter: hash of period => price_id
        processor_plan(:stripe, id_or_period)
      elsif id_or_period.is_a?(Symbol)
        # Getter: specific period
        plan_id_for(:stripe, period: id_or_period)
      else
        # Setter: single price ID (backward compatible)
        processor_plan(:stripe, id_or_period)
      end
    end

    # Get all Stripe price IDs as a hash (always returns hash format)
    # @return [Hash] Hash of period => price_id, or { default: price_id } for single-price plans
    def stripe_prices
      ids = plan_id_for(:stripe)
      return {} if ids.nil?
      return ids if ids.is_a?(Hash)
      { default: ids } # Wrap single ID in hash for consistency
    end

    # Check if this plan matches a given processor price ID
    # Works with both single-price and multi-period plans
    # @param processor_id [String] The price ID to match
    # @return [Boolean] True if this plan includes the given price ID
    def matches_processor_id?(processor_id)
      processor_plan_ids.values.any? do |ids|
        if ids.is_a?(Hash)
          ids.values.include?(processor_id)
        else
          ids == processor_id
        end
      end
    end

    # Create a checkout session for this subscription plan
    # @param user [Object] The user creating the checkout session
    # @param success_url [String] URL to redirect after successful checkout
    # @param cancel_url [String] URL to redirect if checkout is cancelled
    # @param processor [Symbol] Payment processor to use (default: :stripe)
    # @param period [Symbol, nil] Billing period for multi-period plans (e.g., :month, :year)
    #
    # @example Single-price plan (backward compatible)
    #   plan.create_checkout_session(user, success_url: "/success", cancel_url: "/cancel")
    #
    # @example Multi-period plan (must specify period)
    #   plan.create_checkout_session(user, success_url: "/success", cancel_url: "/cancel", period: :month)
    #   plan.create_checkout_session(user, success_url: "/success", cancel_url: "/cancel", period: :year)
    def create_checkout_session(user, success_url:, cancel_url:, processor: :stripe, period: nil)
      raise ArgumentError, "User must respond to payment_processor" unless user.respond_to?(:payment_processor)
      raise ArgumentError, "No fulfillment period configured for plan: #{name}" unless fulfillment_period

      plan_ids = plan_id_for(processor)
      raise ArgumentError, "No #{processor.to_s.titleize} plan ID configured for plan: #{name}" unless plan_ids

      # Determine which price ID to use
      plan_id = if plan_ids.is_a?(Hash)
        # Multi-period plan: period is required
        raise ArgumentError, "This plan has multiple billing periods (#{plan_ids.keys.join(', ')}). Please specify period: parameter (e.g., period: :month)" if period.nil?
        plan_ids[period.to_sym] || raise(ArgumentError, "Period #{period.inspect} not found. Available periods: #{plan_ids.keys.inspect}")
      else
        # Single-price plan: use the ID directly
        plan_ids
      end

      case processor
      when :stripe
        create_stripe_checkout_session(user, plan_id, success_url, cancel_url)
      else
        raise ArgumentError, "Unsupported payment processor: #{processor}"
      end
    end

    # =========================================
    # Validation
    # =========================================

    def validate!
      raise ArgumentError, "Name can't be blank" if name.blank?
      raise ArgumentError, "Credits per period must be greater than 0" unless credits_per_period.to_i.positive?
      raise ArgumentError, "Fulfillment period must be set" if fulfillment_period.nil?
      raise ArgumentError, "Signup bonus credits must be greater than or equal to 0" if signup_bonus_credits.to_i.negative?
      raise ArgumentError, "Trial credits must be greater than or equal to 0" if trial_credits.to_i.negative?
      true
    end

    # =========================================
    # Helper Methods
    # =========================================

    def fulfillment_period_display
      fulfillment_period.is_a?(ActiveSupport::Duration) ? fulfillment_period.inspect : fulfillment_period
    end

    def parsed_fulfillment_period
      UsageCredits::PeriodParser.parse_period(@fulfillment_period)
    end

    def create_stripe_checkout_session(user, plan_id, success_url, cancel_url)
      user.payment_processor.checkout(
        mode: "subscription",
        line_items: [{
          price: plan_id,
          quantity: 1
        }],
        success_url: success_url,
        cancel_url: cancel_url,
        subscription_data: { metadata: base_metadata }
      )
    end

    def base_metadata
      {
        purchase_type: "credit_subscription",
        subscription_name: name,
        fulfillment_period: fulfillment_period_display,
        credits_per_period: credits_per_period,
        signup_bonus_credits: signup_bonus_credits,
        trial_credits: trial_credits,
        rollover_enabled: rollover_enabled,
        expire_credits_on_cancel: expire_credits_on_cancel,
        credit_expiration_period: credit_expiration_period&.to_i,
        metadata: metadata
      }
    end

    # =========================================
    # DSL Helper Classes
    # =========================================

    # CreditGiver is a helper class that enables the DSL within `subscription_plan` blocks to define credit amounts.
    #
    # This is what allows us to write:
    #   gives 10_000.credits.every(:month)
    #
    # Instead of:
    #   set_credits(10_000)
    #   set_period(:month)
    class CreditGiver
      def initialize(plan)
        @plan = plan
      end

      def every(period)
        @plan.fulfillment_period = UsageCredits::PeriodParser.normalize_period(period)
        @plan
      end
    end

  end
end
