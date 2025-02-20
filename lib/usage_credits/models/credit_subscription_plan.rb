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

    MIN_PERIOD = 1.day

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

    # Set the processor-specific plan ID
    def processor_plan(processor, id)
      processor_plan_ids[processor.to_sym] = id
    end

    # Get the plan ID for a specific processor
    def plan_id_for(processor)
      processor_plan_ids[processor.to_sym]
    end

    # Shorthand for Stripe price ID
    def stripe_price(id = nil)
      if id.nil?
        plan_id_for(:stripe) # getter
      else
        processor_plan(:stripe, id) # setter
      end
    end

    # Create a checkout session for this subscription plan
    def create_checkout_session(user, success_url:, cancel_url:, processor: :stripe)
      raise ArgumentError, "User must respond to payment_processor" unless user.respond_to?(:payment_processor)
      raise ArgumentError, "No fulfillment period configured for plan: #{name}" unless fulfillment_period

      plan_id = plan_id_for(processor)
      raise ArgumentError, "No #{processor.to_s.titleize} plan ID configured for plan: #{name}" unless plan_id

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
