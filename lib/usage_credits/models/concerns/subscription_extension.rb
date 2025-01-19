# frozen_string_literal: true

module UsageCredits
  # Extends Pay::Subscription to handle credit allocation
  module SubscriptionExtension
    extend ActiveSupport::Concern

    included do
      after_create :setup_subscription_credits

      # TODO: undefined method `before_cancel' for class Pay::Subscription (NoMethodError)
      # before_cancel :handle_subscription_cancellation

      # TODO: undefined method `after_resume' for class Pay::Subscription
      # after_resume :handle_subscription_resumed
    end

    # Get the credit rule for this subscription's plan
    def credit_rule
      @credit_rule ||= UsageCredits.subscription_rules[processor_plan]
    end

    # Check if this subscription provides credits
    def provides_credits?
      credit_rule.present?
    end

    # Get monthly credit allowance
    def monthly_credits
      credit_rule&.monthly_credits || 0
    end

    # Get initial signup bonus credits
    def initial_credits
      credit_rule&.initial_credits || 0
    end

    # Check if credits roll over month to month
    def rollover_credits?
      credit_rule&.rollover || false
    end

    private

    def setup_subscription_credits
      return unless provides_credits?

      if trial?
        setup_trial_credits
      else
        setup_regular_credits
      end
    end

    def setup_trial_credits
      return unless credit_rule&.trial_credits

      customer.owner.credit_wallet.add_credits(
        credit_rule.trial_credits,
        metadata: {
          source: :subscription_trial,
          subscription_id: id
        }
      )
    end

    def setup_regular_credits
      # Add initial signup bonus if any
      if initial_credits.positive?
        customer.owner.credit_wallet.add_credits(
          initial_credits,
          metadata: {
            source: :subscription_signup_bonus,
            subscription_id: id
          }
        )
      end

      # Add first month's credits
      add_monthly_credits
    end

    def add_monthly_credits
      return unless monthly_credits.positive?

      if rollover_credits?
        add_rollover_credits
      else
        reset_and_add_credits
      end
    end

    def add_rollover_credits
      customer.owner.credit_wallet.add_credits(
        monthly_credits,
        metadata: {
          source: :subscription_monthly,
          subscription_id: id
        }
      )
    end

    def reset_and_add_credits
      wallet = customer.owner.credit_wallet
      wallet.update!(balance: monthly_credits)
      wallet.transactions.create!(
        amount: monthly_credits,
        category: :subscription_monthly_reset,
        metadata: { subscription_id: id }
      )
    end

    def handle_subscription_cancellation
      return unless provides_credits?

      # Handle any cleanup needed when subscription is cancelled
      # For example, schedule credit expiration
      if credit_rule.expire_credits_on_cancel
        schedule_credit_expiration
      end
    end

    def handle_subscription_resumed
      return unless provides_credits?

      # Re-add monthly credits if needed
      add_monthly_credits
    end

    def schedule_credit_expiration
      return unless credit_rule.credit_expiration_period

      expiration_date = Time.current + credit_rule.credit_expiration_period

      # Schedule a background job to expire credits
      UsageCredits::ExpireCreditsJob.set(wait_until: expiration_date)
                                   .perform_later(customer.owner.credit_wallet)
    end
  end
end
