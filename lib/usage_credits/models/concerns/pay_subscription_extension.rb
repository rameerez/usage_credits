# frozen_string_literal: true

module UsageCredits
  # Extends Pay::Subscription with credit functionality
  module PaySubscriptionExtension
    extend ActiveSupport::Concern

    included do
      after_initialize :init_metadata
      after_create :setup_subscription_credits
      after_update :handle_subscription_status_change
      after_commit :handle_credit_fulfillment, if: :should_handle_credits?
      after_commit :handle_credit_expiration, if: :should_handle_expiration?

      # TODO: FIX ERROR undefined method `before_cancel' for class Pay::Subscription (NoMethodError)
      # before_cancel :handle_subscription_cancellation

      # TODO: FIX ERROR undefined method `after_resume' for class Pay::Subscription
      # after_resume :handle_subscription_resumed
    end

    def init_metadata
      self.metadata ||= {}
      self.data ||= {}
    end

    # Get the credit rule for this subscription
    def credit_rule
      return @credit_rule if defined?(@credit_rule)
      @credit_rule = UsageCredits.configuration.subscription_rules[processor_plan.to_sym]
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
      return unless credit_rule&.trial_credits&.positive?

      customer.owner.credit_wallet.add_credits(
        credit_rule.trial_credits,
        category: :subscription_trial,
        metadata: {
          subscription_id: id,
          processor: processor,
          plan: processor_plan,
          trial_start: trial_ends_at&.beginning_of_day,
          trial_end: trial_ends_at&.end_of_day
        },
        expires_at: trial_ends_at
      )
    end

    def handle_trial_conversion
      return unless saved_change_to_status? && status == "active" && status_before_last_save == "trialing"
      return unless credit_rule

      wallet = customer.owner.credit_wallet

      # Add signup bonus if not already given
      if !metadata["signup_bonus_given"] && credit_rule.initial_credits&.positive?
        wallet.add_credits(
          credit_rule.initial_credits,
          category: :subscription_signup_bonus,
          metadata: {
            subscription_id: id,
            processor: processor,
            plan: processor_plan,
            converted_from_trial: true,
            converted_at: Time.current
          }
        )
        update_column(:metadata, metadata.merge("signup_bonus_given" => true))
      end

      # Add first month's credits
      add_monthly_credits
    end

    def handle_trial_expiration
      return unless status == "trialing" && trial_ends_at&.past? && !metadata["trial_expired"]
      return unless credit_rule&.trial_credits&.positive?

      Rails.logger.info "Handling trial expiration for subscription #{id}"
      Rails.logger.info "  Trial ended at: #{trial_ends_at}"

      wallet = customer.owner.credit_wallet
      wallet.expire_credits_at(
        trial_ends_at,
        metadata: {
          subscription_id: id,
          processor: processor,
          plan: processor_plan,
          reason: "trial_expired",
          trial_start: trial_ends_at&.beginning_of_day,
          trial_end: trial_ends_at&.end_of_day
        },
        category: :subscription_trial_expired
      )

      update_column(:metadata, metadata.merge("trial_expired" => true))
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
      return unless credit_rule
      return unless ends_at.present?

      Rails.logger.info "Handling subscription cancellation for subscription #{id}"
      Rails.logger.info "  Ends at: #{ends_at}"
      Rails.logger.info "  Expiration period: #{credit_rule.credit_expiration_period}"

      # Handle any cleanup needed when subscription is cancelled
      if credit_rule.expire_credits_on_cancel
        expiry_time = ends_at
        if credit_rule.credit_expiration_period
          expiry_time += credit_rule.credit_expiration_period
          Rails.logger.info "  Credits will expire at: #{expiry_time} (after grace period)"
        else
          Rails.logger.info "  Credits will expire at: #{expiry_time} (no grace period)"
        end

        customer.owner.credit_wallet.expire_credits_at(
          expiry_time,
          metadata: {
            subscription_id: id,
            processor: processor,
            plan: processor_plan,
            reason: "subscription_cancelled",
            cancelled_at: Time.current,
            ends_at: ends_at,
            grace_period: credit_rule.credit_expiration_period&.to_i
          }
        )
      end

      update_column(:metadata, metadata.merge(
        "cancellation_processed" => true,
        "cancelled_at" => Time.current.iso8601,
        "credits_expire_at" => expiry_time&.iso8601
      ))
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

      # Handle credit fulfillment when:
      # 1. Subscription becomes active
      # 2. Subscription renews (new billing cycle)
      # 3. Plan changes
      # 4. Trial starts
      if saved_change_to_status?
        case status
        when "active"
          return true if ["incomplete", "trialing"].include?(status_before_last_save)
        when "trialing"
          return true
        end
      end

      # Handle plan changes
      return true if processor_plan_previously_changed?

      # Handle billing cycle renewal
      return true if current_period_start_previously_changed?

      false
    end

    def should_handle_expiration?
      return false unless processor_plan.present?
      return false unless customer&.owner&.respond_to?(:credit_wallet)
      return false unless credit_rule.present?

      if saved_change_to_status?
        # Expire credits when:
        # 1. Subscription is cancelled
        # 2. Subscription becomes unpaid
        # 3. Subscription is paused (if configured)
        # 4. Trial expires without conversion
        case status
        when "canceled"
          return true if ["active", "trialing", "past_due"].include?(status_before_last_save)
        when "unpaid"
          return true if ["active", "trialing", "past_due"].include?(status_before_last_save)
        when "paused"
          return true if credit_rule.respond_to?(:expire_on_pause) && credit_rule.expire_on_pause
        when "incomplete"
          return true if trial_ends_at&.past? && !metadata["trial_expired"]
        end
      end

      false
    end

    def handle_credit_fulfillment
      rule = credit_rule
      return unless rule
      return unless customer&.owner&.respond_to?(:credit_wallet)

      wallet = customer.owner.credit_wallet

      case status
      when "active"
        # Handle trial conversion first
        handle_trial_conversion

        # Then handle plan changes or billing cycle renewal
        if processor_plan_previously_changed?
          handle_plan_change(wallet)
        elsif current_period_start_previously_changed?
          handle_billing_cycle_renewal(wallet)
        end

      when "trialing"
        # Setup initial trial credits if not already given
        return unless rule.trial_credits&.positive?
        return if metadata["initial_credits_given"]

        setup_trial_credits
        update_column(:metadata, metadata.merge("initial_credits_given" => true))
      end
    end

    def handle_credit_expiration
      rule = credit_rule
      return unless rule
      return unless customer&.owner&.respond_to?(:credit_wallet)

      wallet = customer.owner.credit_wallet

      expiry_date = case status
                    when "canceled"
                      if rule.credit_expiration_period
                        ends_at + rule.credit_expiration_period
                      else
                        ends_at
                      end
                    when "unpaid"
                      Time.current
                    when "paused"
                      if rule.respond_to?(:expire_on_pause) && rule.expire_on_pause
                        pause_starts_at
                      end
                    when "incomplete"
                      if trial_ends_at&.past? && !metadata["trial_expired"]
                        trial_ends_at
                      end
                    end

      return unless expiry_date

      # Create an expiration record
      wallet.expire_credits_at(
        expiry_date,
        metadata: {
          subscription_id: id,
          processor: processor,
          plan: processor_plan,
          reason: status,
          previous_status: status_before_last_save,
          expired_at: Time.current
        }
      )

      # Mark trial as expired if applicable
      if status == "incomplete" && trial_ends_at&.past? && !metadata["trial_expired"]
        update_column(:metadata, metadata.merge("trial_expired" => true))
      end
    end

    def handle_plan_change(wallet)
      old_rule = UsageCredits.subscription_rules[processor_plan_before_last_save&.to_sym]
      new_rule = credit_rule

      old_amount = old_rule&.monthly_credits.to_i
      new_amount = new_rule&.monthly_credits.to_i

      if new_amount > old_amount
        if new_rule.rollover_enabled
          wallet.add_credits(
            new_amount,
            category: :subscription_monthly,
            metadata: {
              subscription_id: id,
              processor: processor,
              plan: processor_plan,
              reason: "plan_upgrade",
              old_plan: processor_plan_before_last_save,
              old_credits: old_amount,
              new_credits: new_amount,
              period_start: current_period_start,
              period_end: current_period_end,
              upgraded_at: Time.current
            }
          )
        else
          # Non-rollover plan => reset to new_amount
          if wallet.credits.positive?
            wallet.expire_credits_at(
              Time.current,
              metadata: {
                subscription_id: id,
                processor: processor,
                plan: processor_plan,
                reason: "plan_upgrade_reset",
                old_plan: processor_plan_before_last_save,
                old_credits: old_amount,
                new_credits: new_amount
              }
            )
            wallet.reload
          end

          wallet.add_credits(
            new_amount,
            category: :subscription_monthly_reset,
            metadata: {
              subscription_id: id,
              processor: processor,
              plan: processor_plan,
              reason: "plan_upgrade",
              old_plan: processor_plan_before_last_save,
              old_credits: old_amount,
              new_credits: new_amount,
              period_start: current_period_start,
              period_end: current_period_end,
              upgraded_at: Time.current
            }
          )
        end
      elsif new_amount < old_amount
        update_column(:metadata, metadata.merge("previous_plan" => processor_plan_before_last_save))
      end
    end

    def handle_billing_cycle_renewal(wallet)
      return unless credit_rule

      # Always reset credits on billing cycle renewal if:
      # 1. Credits don't roll over
      # 2. There was a downgrade in the previous period
      previous_plan = metadata["previous_plan"]&.to_sym
      if !credit_rule.rollover_enabled || (previous_plan && UsageCredits.subscription_rules[previous_plan]&.monthly_credits.to_i > credit_rule.monthly_credits)
        if wallet.credits.positive?
          wallet.expire_credits_at(
            Time.current,
            metadata: {
              subscription_id: id,
              processor: processor,
              plan: processor_plan,
              reason: "billing_cycle_reset",
              previous_balance: wallet.credits,
              previous_plan: previous_plan
            }
          )
          wallet.reload
        end

        wallet.add_credits(
          credit_rule.monthly_credits,
          category: :subscription_monthly_reset,
          metadata: {
            subscription_id: id,
            processor: processor,
            plan: processor_plan,
            reason: "billing_cycle_renewal",
            period_start: current_period_start,
            period_end: current_period_end,
            renewed_at: Time.current,
            previous_plan: previous_plan
          }
        )
      else
        wallet.add_credits(
          credit_rule.monthly_credits,
          category: :subscription_monthly,
          metadata: {
            subscription_id: id,
            processor: processor,
            plan: processor_plan,
            reason: "billing_cycle_renewal",
            previous_balance: wallet.credits,
            period_start: current_period_start,
            period_end: current_period_end,
            renewed_at: Time.current
          }
        )
      end
    end

    def add_monthly_credits
      if credit_rule.rollover_enabled
        add_rollover_credits
      else
        reset_and_add_credits
      end
    end

    def add_rollover_credits
      customer.owner.credit_wallet.add_credits(
        credit_rule.monthly_credits,
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
      wallet.update!(balance: credit_rule.monthly_credits)
      wallet.transactions.create!(
        amount: credit_rule.monthly_credits,
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
  end
end
