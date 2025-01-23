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

    VALID_PERIODS = {
      month: [:month, :monthly],
      year: [:year, :yearly, :annually],
      quarter: [:quarter, :quarterly]
    }.freeze

    # Helper class that enables the DSL for credit amounts.
    # This is what allows us to write:
    #   gives 10_000.credits.per(:month)
    # Instead of:
    #   set_credits(10_000)
    #   set_period(:month)
    class CreditGiver
      def initialize(plan)
        @plan = plan
      end

      # Set how often credits are given
      # @param period [:month, :year, :quarter] The fulfillment period
      def per(period)
        @plan.fulfillment_period = normalize_period(period)
        @plan
      end

      private

      # Normalize period aliases to their canonical form
      # @example
      #   normalize_period(:monthly)  # => :month
      #   normalize_period(:yearly)   # => :year
      #   normalize_period(:annually) # => :year
      def normalize_period(period)
        VALID_PERIODS.each do |normalized, aliases|
          return normalized if aliases.include?(period)
        end
        raise ArgumentError, "Unsupported period: #{period}. Supported periods: #{VALID_PERIODS.values.flatten.inspect}"
      end
    end

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

    # Get the plan ID for a specific processor
    def plan_id_for(processor)
      processor_plan_ids[processor.to_sym]
    end

    # Set the processor-specific plan ID
    def processor_plan(processor, id)
      processor_plan_ids[processor.to_sym] = id
    end

    # Shorthand DSL for setting the Stripe Price ID for this plan
    def stripe_price(id)
      processor_plan(:stripe, id)
    end

    # Set credits given each fulfillment period
    def gives(amount)
      @credits_per_period = amount.to_i
      CreditGiver.new(self)
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

    # Add custom metadata to the subscription plan
    def meta(hash)
      @metadata.merge!(hash)
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

    private

    def normalize_period(period)
      return nil unless period

      VALID_PERIODS.each do |normalized, aliases|
        return normalized if aliases.include?(period)
      end
      raise ArgumentError, "Unsupported period: #{period}. Supported periods: #{VALID_PERIODS.values.flatten.inspect}"
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
        payment_intent_data: { metadata: base_metadata },
        subscription_data: { metadata: base_metadata }
      )
    end

    def base_metadata
      {
        purchase_type: "credit_subscription",
        subscription_name: name,
        fulfillment_period: fulfillment_period,
        credits_per_period: credits_per_period,
        signup_bonus_credits: signup_bonus_credits,
        trial_credits: trial_credits,
        rollover_enabled: rollover_enabled,
        expire_credits_on_cancel: expire_credits_on_cancel,
        credit_expiration_period: credit_expiration_period&.to_i,
        metadata: metadata
      }
    end
  end
end
