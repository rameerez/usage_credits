# frozen_string_literal: true

module UsageCredits
  # Extends Pay::Subscription with credit functionality.
  #
  # This module is responsible for:
  #   1. Monitoring subscription lifecycle events
  #   2. Fulfilling credits at the right times
  #   3. Handling credit expiration
  #   4. Managing trial periods
  #
  # Credit fulfillment happens on:
  #   - Subscription creation (signup bonus + first period)
  #   - Trial start (trial credits)
  #   - Trial conversion (signup bonus if not given + first period)
  #   - Period renewal (new credits, with optional rollover)
  #   - Plan changes (prorated credits)
  #
  # Credit expiration happens on:
  #   - Trial expiration without conversion
  #   - Subscription cancellation (with optional grace period)
  #   - Period renewal (if no rollover)
  #   - Plan downgrades
  #
  # @see CreditSubscriptionPlan for the plan configuration
  module PaySubscriptionExtension
    extend ActiveSupport::Concern

    included do
      after_initialize :init_metadata
      after_commit :fulfill_signup_bonus_credits!, on: :create
      after_update :handle_subscription_status_change
      after_commit :handle_credit_fulfillment, if: :should_handle_credits?
      after_commit :handle_credit_expiration, if: :should_handle_expiration?
    end

    def init_metadata
      self.metadata ||= {}
      self.data ||= {}
    end

    # Get the credit plan for this subscription
    def credit_subscription_plan
      return @credit_subscription_plan if defined?(@credit_subscription_plan)
      @credit_subscription_plan = UsageCredits.configuration.find_subscription_plan_by_processor_id(processor_plan)
    end

    # Get the processor name
    def processor
      :stripe  # For now, we only support Stripe
    end

    # Get the Stripe Price ID for this subscription plan
    def stripe_price_id
      raise ArgumentError, "This subscription's processor is not Stripe" unless processor == :stripe
      credit_subscription_plan&.stripe_price_id || raise(ArgumentError, "No Stripe Price ID configured for plan: #{processor_plan}")
    end

    # Check if this subscription provides credits
    def provides_credits?
      credit_subscription_plan.present?
    end

    # Get credits given each period
    def credits_per_period
      credit_subscription_plan&.credits_per_period || 0
    end

    # Get signup bonus credits
    def signup_bonus_credits
      credit_subscription_plan&.signup_bonus_credits || 0
    end

    # Get trial credits
    def trial_credits
      credit_subscription_plan&.trial_credits || 0
    end

    # Check if credits roll over between periods
    def rollover_credits?
      credit_subscription_plan&.rollover_enabled
    end

    private

    # Returns true if the subscription has a valid credit wallet to operate on
    def has_valid_wallet?
      return false unless customer&.owner&.respond_to?(:credit_wallet)
      return false unless customer.owner.credit_wallet.present?
      true
    end

    def credits_already_fulfilled?
      customer.owner.credit_wallet.transactions
        .where(category: [:subscription_trial, :subscription_signup_bonus])
        .exists?(['metadata @> ?', { subscription_id: id, credits_fulfilled: true }.to_json])
    end

    def fulfill_signup_bonus_credits!
      return unless provides_credits?
      return unless ["active", "trialing"].include?(status)
      return unless has_valid_wallet?
      return if credits_already_fulfilled?

      Rails.logger.info "Fulfilling initial credits for subscription #{id}"
      Rails.logger.info "  Status: #{status}"
      Rails.logger.info "  Plan: #{processor_plan}"

      begin
        ActiveRecord::Base.transaction do
          if status == "trialing"
            fulfill_trial_credits
          else
            fulfill_regular_credits
          end

          metadata["signup_bonus_credits_fulfilled"] = true
          save!
        end

        Rails.logger.info "Successfully fulfilled initial credits for subscription #{id}"
      rescue StandardError => e
        Rails.logger.error "Failed to fulfill initial credits for subscription #{id}: #{e.message}"
        raise
      end
    end

    def fulfill_trial_credits
      return unless trial_credits&.positive?

      Rails.logger.info "  Fulfilling trial credits: #{trial_credits}"

      customer.owner.credit_wallet.add_credits(
        trial_credits,
        category: :subscription_trial,
        metadata: {
          subscription_id: id,
          processor: processor,
          plan: processor_plan,
          trial_start: trial_ends_at&.beginning_of_day,
          trial_end: trial_ends_at&.end_of_day,
          credits_fulfilled: true,
          fulfilled_at: Time.current
        },
        expires_at: trial_ends_at
      )
    end

    def handle_trial_conversion
      return unless saved_change_to_status? && status == "active" && status_before_last_save == "trialing"
      return unless credit_subscription_plan
      return unless has_valid_wallet?

      Rails.logger.info "Handling trial conversion for subscription #{id}"
      Rails.logger.info "  Plan: #{processor_plan}"

      wallet = customer.owner.credit_wallet

      begin
        ActiveRecord::Base.transaction do
          # Fulfill signup bonus if not already given
          if !metadata["signup_bonus_fulfilled"] && signup_bonus_credits&.positive?
            Rails.logger.info "  Fulfilling signup bonus: #{signup_bonus_credits}"

            wallet.add_credits(
              signup_bonus_credits,
              category: :subscription_signup_bonus,
              metadata: {
                subscription_id: id,
                processor: processor,
                plan: processor_plan,
                converted_from_trial: true,
                converted_at: Time.current,
                credits_fulfilled: true,
                fulfilled_at: Time.current
              }
            )

            metadata["signup_bonus_fulfilled"] = true
            save!
          end

          # Fulfill first period's credits
          fulfill_period_credits
        end

        Rails.logger.info "Successfully handled trial conversion for subscription #{id}"
      rescue StandardError => e
        Rails.logger.error "Failed to handle trial conversion for subscription #{id}: #{e.message}"
        raise
      end
    end

    def handle_trial_expiration
      return unless status == "trialing" && trial_ends_at&.past? && !metadata["trial_expired"]
      return unless trial_credits&.positive?
      return unless has_valid_wallet?

      Rails.logger.info "Handling trial expiration for subscription #{id}"
      Rails.logger.info "  Trial ended at: #{trial_ends_at}"

      begin
        ActiveRecord::Base.transaction do
          wallet = customer.owner.credit_wallet
          wallet.expire_credits_at(
            trial_ends_at,
            metadata: {
              subscription_id: id,
              processor: processor,
              plan: processor_plan,
              reason: "trial_expired",
              trial_start: trial_ends_at&.beginning_of_day,
              trial_end: trial_ends_at&.end_of_day,
              expired_at: Time.current
            },
            category: :subscription_trial_expired
          )

          metadata["trial_expired"] = true
          save!
        end

        Rails.logger.info "Successfully handled trial expiration for subscription #{id}"
      rescue StandardError => e
        Rails.logger.error "Failed to handle trial expiration for subscription #{id}: #{e.message}"
        raise
      end
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
      return unless credit_subscription_plan
      return unless ends_at.present?
      return unless has_valid_wallet?

      Rails.logger.info "Handling subscription cancellation for subscription #{id}"
      Rails.logger.info "  Ends at: #{ends_at}"
      Rails.logger.info "  Expiration period: #{credit_subscription_plan.credit_expiration_period}"

      begin
        ActiveRecord::Base.transaction do
          # Handle any cleanup needed when subscription is cancelled
          if credit_subscription_plan.expire_credits_on_cancel
            expiry_time = ends_at
            if credit_subscription_plan.credit_expiration_period
              expiry_time += credit_subscription_plan.credit_expiration_period
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
                grace_period: credit_subscription_plan.credit_expiration_period&.to_i,
                expired_at: Time.current
              }
            )
          end

          metadata.merge!(
            "cancellation_processed" => true,
            "cancelled_at" => Time.current.iso8601,
            "credits_expire_at" => expiry_time&.iso8601
          )
          save!
        end

        Rails.logger.info "Successfully handled subscription cancellation for subscription #{id}"
      rescue StandardError => e
        Rails.logger.error "Failed to handle subscription cancellation for subscription #{id}: #{e.message}"
        raise
      end
    end

    def handle_subscription_resumed
      return unless provides_credits?
      return unless has_valid_wallet?

      Rails.logger.info "Handling subscription resume for subscription #{id}"

      begin
        # Re-fulfill period credits if needed
        fulfill_period_credits

        Rails.logger.info "Successfully handled subscription resume for subscription #{id}"
      rescue StandardError => e
        Rails.logger.error "Failed to handle subscription resume for subscription #{id}: #{e.message}"
        raise
      end
    end

    def should_handle_credits?
      return false unless processor_plan.present?
      return false unless has_valid_wallet?
      return false unless credit_subscription_plan.present?

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
      return false unless has_valid_wallet?
      return false unless credit_subscription_plan.present?

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
          return true if credit_subscription_plan.respond_to?(:expire_on_pause) && credit_subscription_plan.expire_on_pause
        when "incomplete"
          return true if trial_ends_at&.past? && !metadata["trial_expired"]
        end
      end

      false
    end

    def handle_credit_fulfillment
      plan = credit_subscription_plan
      return unless plan
      return unless has_valid_wallet?

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
        return unless plan.trial_credits&.positive?
        return if metadata["signup_bonus_credits_fulfilled"]

        fulfill_trial_credits
        metadata["signup_bonus_credits_fulfilled"] = true
        save!
      end
    end

    def handle_credit_expiration
      plan = credit_subscription_plan
      return unless plan
      return unless has_valid_wallet?

      wallet = customer.owner.credit_wallet

      expiry_date = case status
                    when "canceled"
                      if plan.credit_expiration_period
                        ends_at + plan.credit_expiration_period
                      else
                        ends_at
                      end
                    when "unpaid"
                      Time.current
                    when "paused"
                      if plan.respond_to?(:expire_on_pause) && plan.expire_on_pause
                        pause_starts_at
                      end
                    when "incomplete"
                      if trial_ends_at&.past? && !metadata["trial_expired"]
                        trial_ends_at
                      end
                    end

      return unless expiry_date

      begin
        ActiveRecord::Base.transaction do
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
            metadata["trial_expired"] = true
            save!
          end
        end

        Rails.logger.info "Successfully handled credit expiration for subscription #{id}"
      rescue StandardError => e
        Rails.logger.error "Failed to handle credit expiration for subscription #{id}: #{e.message}"
        raise
      end
    end

    def handle_plan_change(wallet)
      old_plan = UsageCredits.credit_subscription_plans[processor_plan_before_last_save&.to_sym]
      new_plan = credit_subscription_plan

      old_amount = old_plan&.credits_per_period.to_i
      new_amount = new_plan&.credits_per_period.to_i

      Rails.logger.info "Handling plan change for subscription #{id}"
      Rails.logger.info "  Old plan: #{processor_plan_before_last_save} (#{old_amount} credits)"
      Rails.logger.info "  New plan: #{processor_plan} (#{new_amount} credits)"

      begin
        ActiveRecord::Base.transaction do
          if new_amount > old_amount
            if new_plan.rollover_enabled
              fulfill_rollover_credits(wallet, new_amount, old_amount)
            else
              reset_and_fulfill_credits(wallet, new_amount, old_amount)
            end
          elsif new_amount < old_amount
            metadata["previous_plan"] = processor_plan_before_last_save
            save!
          end
        end

        Rails.logger.info "Successfully handled plan change for subscription #{id}"
      rescue StandardError => e
        Rails.logger.error "Failed to handle plan change for subscription #{id}: #{e.message}"
        raise
      end
    end

    def fulfill_rollover_credits(wallet, new_amount, old_amount)
      wallet.add_credits(
        new_amount,
        category: :subscription_period,
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
          upgraded_at: Time.current,
          credits_fulfilled: true,
          fulfilled_at: Time.current,
          fulfillment_period: credit_subscription_plan.fulfillment_period
        }
      )
    end

    def reset_and_fulfill_credits(wallet, new_amount, old_amount)
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
            new_credits: new_amount,
            expired_at: Time.current,
            fulfillment_period: credit_subscription_plan.fulfillment_period
          }
        )
        wallet.reload
      end

      wallet.add_credits(
        new_amount,
        category: :subscription_period_reset,
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
          upgraded_at: Time.current,
          credits_fulfilled: true,
          fulfilled_at: Time.current,
          fulfillment_period: credit_subscription_plan.fulfillment_period
        }
      )
    end

    def handle_billing_cycle_renewal(wallet)
      return unless credit_subscription_plan

      Rails.logger.info "Handling billing cycle renewal for subscription #{id}"
      Rails.logger.info "  Plan: #{processor_plan}"
      Rails.logger.info "  Credits: #{credits_per_period}"

      begin
        ActiveRecord::Base.transaction do
          # Always reset credits on billing cycle renewal if:
          # 1. Credits don't roll over
          # 2. There was a downgrade in the previous period
          previous_plan = metadata["previous_plan"]&.to_sym
          if !credit_subscription_plan.rollover_enabled || (previous_plan && UsageCredits.credit_subscription_plans[previous_plan]&.credits_per_period.to_i > credits_per_period)
            if wallet.credits.positive?
              wallet.expire_credits_at(
                Time.current,
                metadata: {
                  subscription_id: id,
                  processor: processor,
                  plan: processor_plan,
                  reason: "billing_cycle_reset",
                  previous_balance: wallet.credits,
                  previous_plan: previous_plan,
                  expired_at: Time.current,
                  fulfillment_period: credit_subscription_plan.fulfillment_period
                }
              )
              wallet.reload
            end

            wallet.add_credits(
              credits_per_period,
              category: :subscription_period_reset,
              metadata: {
                subscription_id: id,
                processor: processor,
                plan: processor_plan,
                reason: "billing_cycle_renewal",
                period_start: current_period_start,
                period_end: current_period_end,
                renewed_at: Time.current,
                previous_plan: previous_plan,
                credits_fulfilled: true,
                fulfilled_at: Time.current,
                fulfillment_period: credit_subscription_plan.fulfillment_period
              }
            )
          else
            wallet.add_credits(
              credits_per_period,
              category: :subscription_period,
              metadata: {
                subscription_id: id,
                processor: processor,
                plan: processor_plan,
                reason: "billing_cycle_renewal",
                previous_balance: wallet.credits,
                period_start: current_period_start,
                period_end: current_period_end,
                renewed_at: Time.current,
                credits_fulfilled: true,
                fulfilled_at: Time.current,
                fulfillment_period: credit_subscription_plan.fulfillment_period
              }
            )
          end
        end

        Rails.logger.info "Successfully handled billing cycle renewal for subscription #{id}"
      rescue StandardError => e
        Rails.logger.error "Failed to handle billing cycle renewal for subscription #{id}: #{e.message}"
        raise
      end
    end

    def fulfill_period_credits
      if credit_subscription_plan.rollover_enabled
        fulfill_rollover_credits
      else
        reset_and_fulfill_credits
      end
    end
  end
end
