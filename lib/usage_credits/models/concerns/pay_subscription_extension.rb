# frozen_string_literal: true

module UsageCredits
  # Extension to Pay::Subscription to refill user credits
  # (and/or set up the `Fulfillment` object that the `UsageCredits::FulfillmentJob` will pick up to refill periodically)
  #
  # We'll:
  #   1) Immediately award trial or first-cycle credits on create
  #   2) Create or update a Fulfillment record for future awarding (the fulfillment job will actually do fulfillment)
  #   3) Expire leftover credits on cancellation if needed
  #
  # Explanation:
  #
  # `after_commit :handle_initial_award_and_fulfillment_setup, on: :create`
  #   If the subscription is trialing or active, do immediate awarding and create a Fulfillment for future recurring awarding.
  #
  # Fulfillment
  #   Has next_fulfillment_at set to (Time.current + 1.month), or whenever the first real billing cycle is.
  #
  # `update_fulfillment_on_cancellation`
  #   If the user cancels, we set fulfillment.stops_at = ends_at, so no further awarding is done.
  #   Optionally we can also forcibly expire leftover credits.
  #
  # That’s it. Everything else—like “monthly awarding,” “rollover credits,” etc.—should be handled by the
  # `FulfillmentService#process` method, which checks the plan’s config to decide how many credits to add next time around.

  # If the subscription is trialing or active, do immediate awarding and create a Fulfillment for future recurring awarding.
  module PaySubscriptionExtension
    extend ActiveSupport::Concern

    included do
      # For initial setup and fulfillment, we can't do after_create or on: :create because the subscription first may
      # get created with status "incomplete" and only get updated to status "active" when the payment is cleared
      after_commit :handle_initial_award_and_fulfillment_setup

      after_commit :update_fulfillment_on_renewal,        if: :subscription_renewed?
      after_commit :update_fulfillment_on_cancellation,   if: :subscription_canceled?

      # TODO: handle plan changes (upgrades / downgrades)
      # TODO: handle paused subscriptions (may still have an "active" status?)
    end

    # Identify the usage_credits plan object
    def credit_subscription_plan
      @credit_subscription_plan ||= UsageCredits.configuration.find_subscription_plan_by_processor_id(processor_plan)
    end

    def provides_credits?
      credit_subscription_plan.present?
    end

    private

    # Returns true if the subscription has a valid credit wallet to operate on
    def has_valid_wallet?
      return false unless customer&.owner&.respond_to?(:credit_wallet)
      return false unless customer.owner.credit_wallet.present?
      true
    end

    def credits_already_fulfilled?
      UsageCredits::Fulfillment.exists?(source: self)
    end

    def subscription_renewed?
      (saved_change_to_ends_at? || saved_change_to_current_period_end?) && status == "active"
    end

    def subscription_canceled?
      saved_change_to_status? && status == "canceled"
    end

    # =========================================
    # Actual fulfillment logic
    # =========================================

    # Immediate awarding of first cycle + set up Fulfillment object for subsequent periods
    def handle_initial_award_and_fulfillment_setup
      return unless provides_credits?
      return unless has_valid_wallet?

      # We only do immediate awarding if the subscription is trialing or active
      return unless ["trialing", "active"].include?(status)

      # We'll skip if we already have a fulfillment record
      return if credits_already_fulfilled?

      plan = credit_subscription_plan
      wallet = customer.owner.credit_wallet

      # Using the configured grace period
      credits_expire_at = !plan.rollover_enabled ? (created_at + plan.parsed_fulfillment_period + UsageCredits.configuration.fulfillment_grace_period) : nil

      Rails.logger.info "Fulfilling initial credits for subscription #{id}"
      Rails.logger.info "  Status: #{status}"
      Rails.logger.info "  Plan: #{plan}"

      # Transaction for atomic awarding + fulfillment creation
      ActiveRecord::Base.transaction do

        total_credits_awarded = 0
        transaction_ids = []

        # 1) If this is a trial and not an active subscription: award trial credits, if any
        if status == "trialing" && plan.trial_credits.positive?

          # Immediate awarding of trial credits
          transaction = wallet.add_credits(plan.trial_credits,
            category: "subscription_trial",
            expires_at: trial_ends_at,
            metadata: {
              subscription_id: id,
              reason: "initial_trial_credits",
              plan: processor_plan,
              fulfilled_at: Time.current
            }
          )
          transaction_ids << transaction.id
          total_credits_awarded += plan.trial_credits

        elsif status == "active"

          # Awarding of signup bonus, if any
          if plan.signup_bonus_credits.positive?
            transaction = wallet.add_credits(plan.signup_bonus_credits,
              category: "subscription_signup_bonus",
              metadata: {
                subscription_id: id,
                reason: "signup_bonus",
                plan: processor_plan,
                fulfilled_at: Time.current
              }
            )
            transaction_ids << transaction.id
            total_credits_awarded += plan.signup_bonus_credits
          end

          # Actual awarding of the subscription credits
          if plan.credits_per_period.positive?
            transaction = wallet.add_credits(plan.credits_per_period,
              category: "subscription_credits",
              expires_at: credits_expire_at,  # This will be nil if credit rollover is enabled
              metadata: {
                subscription_id: id,
                reason: "first_cycle",
                plan: processor_plan,
                fulfilled_at: Time.current
              }
            )
            transaction_ids << transaction.id
            total_credits_awarded += plan.credits_per_period
          end
        end

        # 2) Create a Fulfillment record for subsequent awarding
        # Use current_period_start as the base time, falling back to created_at
        period_start = if trial_ends_at && status == "trialing"
                      trial_ends_at
                    else
                      current_period_start || created_at
                    end

        # Ensure next_fulfillment_at is in the future
        next_fulfillment_at = period_start + plan.parsed_fulfillment_period
        next_fulfillment_at = Time.current + plan.parsed_fulfillment_period if next_fulfillment_at <= Time.current

        fulfillment = UsageCredits::Fulfillment.create!(
          wallet: wallet,
          source: self,
          fulfillment_type: "subscription",
          credits_last_fulfillment: total_credits_awarded,
          fulfillment_period: plan.fulfillment_period_display,
          last_fulfilled_at: Time.now,
          next_fulfillment_at: next_fulfillment_at,
          stops_at: ends_at, # Set when the fulfillment will stop; TODO: this will need to get renewed with future payments (updates to the Pay::Subscription model)
          metadata: {
            subscription_id: id,
            plan: processor_plan,
          }
        )

        # Link created transactions to the fulfillment object for traceability
        UsageCredits::Transaction.where(id: transaction_ids).update_all(fulfillment_id: fulfillment.id)
      rescue => e
        Rails.logger.error "Failed to fulfill initial credits for subscription #{id}: #{e.message}"
        raise ActiveRecord::Rollback
      end
    end

    # Handle subscription renewal (we received a new payment for another billing period)
    # Each time the subscription renews and ends_at moves forward,
    # we keep awarding credits because Fulfillment#stops_at also moves forward
    def update_fulfillment_on_renewal
      return unless provides_credits? && has_valid_wallet?

      fulfillment = UsageCredits::Fulfillment.find_by(source: self)
      return unless fulfillment

      ActiveRecord::Base.transaction do
        # Subscription renewed, we can set the new Fulfillment stops_at to the extended date
        fulfillment.update!(stops_at: current_period_end || ends_at)
        Rails.logger.info "Fulfillment #{fulfillment.id} stops_at updated to #{fulfillment.stops_at}"
      rescue => e
        Rails.logger.error "Failed to extend fulfillment period for subscription #{id}: #{e.message}"
        raise ActiveRecord::Rollback
      end
    end


    # If the subscription is canceled, let's set the Fulfillment's stops_at so the job won't keep awarding
    def update_fulfillment_on_cancellation
      plan = credit_subscription_plan
      return unless plan && has_valid_wallet?

      fulfillment = UsageCredits::Fulfillment.find_by(source: self)
      return unless fulfillment

      ActiveRecord::Base.transaction do
        # Subscription cancelled, so stop awarding credits in the future
        fulfillment.update!(stops_at: current_period_end || ends_at)
        Rails.logger.info "Fulfillment #{fulfillment.id} stops_at set to #{fulfillment.stops_at} due to cancellation"
      rescue => e
        Rails.logger.error "Failed to stop credit fulfillment for subscription #{id}: #{e.message}"
        raise ActiveRecord::Rollback
      end

      # TODO: we can also expire already awarded credits here (without making the ledger mutable – we'll need to
      # check if the plan expires credits or not, and if rollover we may need to add a negative transaction to offset
      # the remaining balance)

    end

  end
end
