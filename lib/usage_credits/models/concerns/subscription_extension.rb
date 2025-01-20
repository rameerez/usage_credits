# frozen_string_literal: true

module UsageCredits
  # Extends Pay::Subscription to handle credit allocation
  module SubscriptionExtension
    extend ActiveSupport::Concern

    included do
      after_initialize do
        self.metadata ||= {}
        self.data ||= {}
      end

      after_create :setup_subscription_credits
      after_update :handle_subscription_status_change
      after_commit :handle_credit_fulfillment, on: [:create, :update], if: :should_handle_credits?
      after_commit :handle_credit_expiration, on: :update, if: :should_expire_credits?

      # TODO: undefined method `before_cancel' for class Pay::Subscription (NoMethodError)
      # before_cancel :handle_subscription_cancellation

      # TODO: undefined method `after_resume' for class Pay::Subscription
      # after_resume :handle_subscription_resumed
    end

    # Get the credit rule for this subscription's plan
    def credit_rule
      @credit_rule ||= UsageCredits.subscription_rules[processor_plan.to_sym]
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
      credit_rule&.rollover_enabled
    end

    # Get the processor name
    def processor
      data&.dig("processor") || customer&.processor
    end

    private

    def setup_subscription_credits
      return unless provides_credits?
      return unless ["active", "trialing"].include?(status)
      return if metadata["initial_credits_given"]

      if status == "trialing"
        setup_trial_credits
      else
        setup_regular_credits
      end

      update_column(:metadata, metadata.merge("initial_credits_given" => true))
    end

    def setup_trial_credits
      return unless credit_rule&.trial_credits

      customer.owner.credit_wallet.add_credits(
        credit_rule.trial_credits,
        category: :subscription_trial,
        metadata: {
          subscription_id: id,
          processor: processor,
          plan: processor_plan
        },
        expires_at: trial_ends_at
      )
    end

    def setup_regular_credits
      # Add initial signup bonus if any
      if initial_credits.positive?
        customer.owner.credit_wallet.add_credits(
          initial_credits,
          category: :subscription_signup_bonus,
          metadata: {
            subscription_id: id,
            processor: processor,
            plan: processor_plan
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
        category: :subscription_monthly,
        metadata: {
          subscription_id: id,
          processor: processor,
          plan: processor_plan,
          period_start: current_period_start,
          period_end: current_period_end
        }
      )
    end

    def reset_and_add_credits
      wallet = customer.owner.credit_wallet
      wallet.update!(balance: monthly_credits)
      wallet.transactions.create!(
        amount: monthly_credits,
        category: :subscription_monthly_reset,
        metadata: {
          subscription_id: id,
          processor: processor,
          plan: processor_plan,
          period_start: current_period_start,
          period_end: current_period_end
        }
      )
    end

    def handle_subscription_status_change
      return unless saved_change_to_status?

      case status
      when "canceled"
        handle_subscription_cancellation
      when "active"
        handle_subscription_resumed if status_before_last_save == "canceled"
      end
    end

    def handle_subscription_cancellation
      return unless provides_credits?

      # Handle any cleanup needed when subscription is cancelled
      if credit_rule.expire_credits_on_cancel && ends_at.present?
        customer.owner.credit_wallet.transactions.create!(
          amount: 0,  # No credits added, just setting expiration
          category: :subscription_credits,
          metadata: {
            subscription_id: id,
            processor: processor,
            plan: processor_plan,
            reason: "subscription_cancelled"
          },
          expires_at: ends_at
        )
      end
    end

    def handle_subscription_resumed
      return unless provides_credits?

      # Re-add monthly credits if needed
      add_monthly_credits
    end

    def should_handle_credits?
      return false unless processor_plan.present?
      return false unless customer&.owner&.respond_to?(:credit_wallet)
      return false unless credit_rule.present?

      if saved_change_to_status?
        old_status = status_before_last_save

        # Give credits when:
        # 1. Subscription becomes active (not from past_due)
        # 2. Trial starts (first time only)
        # 3. Subscription is resumed from pause
        case status
        when "active"
          return true if !["active", "past_due"].include?(old_status)
        when "trialing"
          return true if old_status != "trialing" && !metadata["initial_credits_given"]
        end
      end

      false
    end

    def should_expire_credits?
      return false unless processor_plan.present?
      return false unless customer&.owner&.respond_to?(:credit_wallet)
      return false unless credit_rule.present?

      if saved_change_to_status?
        old_status = status_before_last_save

        # Expire credits when:
        # 1. Subscription is cancelled
        # 2. Subscription becomes unpaid
        # 3. Subscription is paused
        case status
        when "canceled", "unpaid"
          return true if ["active", "trialing", "past_due"].include?(old_status)
        when "paused"
          return true if credit_rule.expire_on_pause
        end
      end

      false
    end

    def handle_credit_fulfillment
      rule = credit_rule
      return unless rule

      wallet = customer.owner.credit_wallet

      case status
      when "active"
        # Give signup bonus only on first activation
        if !metadata["signup_bonus_given"]
          wallet.add_credits(
            rule.initial_credits,
            category: :subscription_signup_bonus,
            metadata: {
              subscription_id: id,
              processor: processor,
              plan: processor_plan
            }
          )
          update_column(:metadata, metadata.merge("signup_bonus_given" => true))
        end

        # Add monthly credits
        if rule.rollover_enabled
          wallet.add_credits(
            rule.monthly_credits,
            category: :subscription_monthly,
            metadata: {
              subscription_id: id,
              processor: processor,
              plan: processor_plan,
              period_start: current_period_start,
              period_end: current_period_end
            }
          )
        else
          wallet.update!(balance: rule.monthly_credits)
          wallet.transactions.create!(
            amount: rule.monthly_credits,
            category: :subscription_monthly_reset,
            metadata: {
              subscription_id: id,
              processor: processor,
              plan: processor_plan,
              period_start: current_period_start,
              period_end: current_period_end
            }
          )
        end

      when "trialing"
        return unless rule.trial_credits&.positive?
        return if metadata["initial_credits_given"]

        wallet.add_credits(
          rule.trial_credits,
          category: :subscription_trial,
          metadata: {
            subscription_id: id,
            processor: processor,
            plan: processor_plan
          },
          expires_at: trial_ends_at
        )
        update_column(:metadata, metadata.merge("initial_credits_given" => true))
      end
    end

    def handle_credit_expiration
      rule = credit_rule
      return unless rule

      expiry_date = case status
        when "canceled" then ends_at
        when "unpaid" then Time.current
        when "paused" then pause_starts_at
        else Time.current
      end

      if rule.expire_credits_on_cancel || (status == "paused" && rule.expire_on_pause)
        customer.owner.credit_wallet.expire_credits_at(
          expiry_date,
          metadata: {
            subscription_id: id,
            processor: processor,
            plan: processor_plan,
            reason: status
          }
        )
      end
    end
  end
end
