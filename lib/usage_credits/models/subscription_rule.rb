# frozen_string_literal: true

module UsageCredits
  # Defines credit rules for subscriptions
  class SubscriptionRule
    attr_reader :name, :monthly_credits, :initial_credits, :trial_credits,
                :rollover_enabled, :expire_credits_on_cancel, :credit_expiration_period,
                :metadata

    def initialize(name)
      @name = name
      @monthly_credits = 0
      @initial_credits = 0
      @trial_credits = 0
      @rollover_enabled = false
      @expire_credits_on_cancel = false
      @credit_expiration_period = nil
      @metadata = {}
    end

    # More intuitive monthly credit setting
    def gives(amount)
      @monthly_credits = amount.to_i
    end

    # More intuitive signup bonus setting
    def signup_bonus(amount)
      @initial_credits = amount.to_i
    end

    # More intuitive trial credit setting
    def trial_includes(amount)
      @trial_credits = amount.to_i
    end

    # More intuitive rollover setting
    def unused_credits(behavior)
      @rollover_enabled = (behavior == :rollover)
    end

    # More intuitive expiration setting
    def expire_after(duration)
      @expire_credits_on_cancel = true
      @credit_expiration_period = duration.is_a?(UsageCredits::TimeAmount) ? duration.to_i : duration
    end

    # Add metadata
    def meta(hash)
      @metadata.merge!(hash)
    end

    # Apply the rule to a subscription
    def apply_to_subscription(subscription)
      wallet = subscription.customer.owner.credit_wallet

      if subscription.trial?
        apply_trial_credits(wallet, subscription)
      else
        apply_regular_credits(wallet, subscription)
      end
    end

    private

    def apply_trial_credits(wallet, subscription)
      return unless trial_credits.positive?

      wallet.add_credits(
        trial_credits,
        metadata: {
          source: :subscription_trial,
          subscription_id: subscription.id,
          subscription_name: subscription.name
        },
        category: :subscription_trial,
        expires_at: subscription.trial_ends_at
      )
    end

    def apply_regular_credits(wallet, subscription)
      # Add initial signup bonus if any
      if initial_credits.positive?
        wallet.add_credits(
          initial_credits,
          metadata: {
            source: :subscription_signup_bonus,
            subscription_id: subscription.id,
            subscription_name: subscription.name
          },
          category: :subscription_signup_bonus
        )
      end

      # Add monthly credits
      if monthly_credits.positive?
        if rollover_enabled
          add_rollover_credits(wallet, subscription)
        else
          reset_and_add_credits(wallet, subscription)
        end
      end
    end

    def add_rollover_credits(wallet, subscription)
      wallet.add_credits(
        monthly_credits,
        metadata: {
          source: :subscription_monthly,
          subscription_id: subscription.id,
          subscription_name: subscription.name
        },
        category: :subscription_monthly
      )
    end

    def reset_and_add_credits(wallet, subscription)
      wallet.update!(balance: monthly_credits)
      wallet.transactions.create!(
        amount: monthly_credits,
        category: :subscription_monthly_reset,
        metadata: {
          subscription_id: subscription.id,
          subscription_name: subscription.name
        }
      )
    end
  end
end
