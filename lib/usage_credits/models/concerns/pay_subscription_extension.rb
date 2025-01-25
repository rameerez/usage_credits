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
  #   Let your monthly/quarterly plan define how to parse "1.month" etc. That’s exactly how the FulfillmentService does it.
  #
  # `handle_cancellation_expiration`
  #   If the user cancels, you can set fulfillment.expires_at = ends_at, so no further awarding is done.
  #   Optionally you also forcibly expire leftover credits.
  #
  # That’s it. Everything else—like “monthly awarding,” “rollover credits,” etc.—should be handled by the
  # `FulfillmentService#process` method, which checks the plan’s config to decide how many credits to add next time around.

  # If the subscription is trialing or active, do immediate awarding and create a Fulfillment for future recurring awarding.
  module PaySubscriptionExtension
    extend ActiveSupport::Concern

    included do
      after_commit :handle_initial_award_and_fulfillment_setup, on: :create
      after_commit :handle_cancellation_expiration, if: :should_handle_cancellation_expiration?
      # TODO: handle plan changes
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

    # Decide if we need to handle cancellation
    def should_handle_cancellation_expiration?
      return false unless saved_change_to_status?
      return false unless status == "canceled"
      return false unless provides_credits?
      true
    end

    # Immediate awarding of first cycle
    def handle_initial_award_and_fulfillment_setup
      return unless provides_credits?
      return unless has_valid_wallet?

      # We only do immediate awarding if the subscription is trialing or active
      return unless ["trialing", "active"].include?(status)

      # We'll skip if we already have a fulfillment record
      return if credits_already_fulfilled?

      plan = credit_subscription_plan
      wallet = customer.owner.credit_wallet

      Rails.logger.info "Fulfilling initial credits for subscription #{id}"
      Rails.logger.info "  Status: #{status}"
      Rails.logger.info "  Plan: #{processor_plan}"

      # Transaction for atomic awarding + fulfillment creation
      ActiveRecord::Base.transaction do

        # 1) Award initial or trial credits immediately
        if status == "trialing" && plan.trial_credits.positive?

          # Immediate awarding of trial credits
          wallet.add_credits(plan.trial_credits,
            category: "subscription_trial",
            expires_at: trial_ends_at,
            metadata: {
              subscription_id: id,
              reason: "initial_trial_credits",
              plan: processor_plan,
              fulfilled_at: Time.current
            }
          )

        elsif status == "active"

          # Awarding of signup bonus + first cycle
          if plan.signup_bonus_credits.positive?
            wallet.add_credits(plan.signup_bonus_credits,
              category: "subscription_signup_bonus",
              metadata: {
                subscription_id: id,
                reason: "signup_bonus",
                plan: processor_plan,
                fulfilled_at: Time.current
              }
            )
          end

          if plan.credits_per_period.positive?
            wallet.add_credits(plan.credits_per_period,
              category: "subscription_credits",
              metadata: {
                subscription_id: id,
                reason: "first_cycle",
                plan: processor_plan,
                fulfilled_at: Time.current
              }
            )
          end
        end

        # 2) Create a Fulfillment record for subsequent awarding
        period_start = (trial_ends_at && status == "trialing") ? trial_ends_at : created_at
        UsageCredits::Fulfillment.create!(
          wallet: wallet,
          source: self,
          fulfillment_type: "subscription",
          last_fulfillment_credits: 0, # or sum of what you just awarded
          fulfillment_period: plan.fulfillment_period, # e.g. "1.month"
          last_fulfillment_at: Time.now,
          next_fulfillment_at: period_start + plan.parsed_fulfillment_period,
          metadata: {
            subscription_id: id,
            plan: processor_plan,
            # any other relevant info
          }
        )
      end
    end

    # If the subscription is canceled, let's mark the Fulfillment expired
    def handle_cancellation_expiration
      # Only triggers if status changed to canceled
      # We'll set the Fulfillment's expires_at so the job won't keep awarding
      plan = credit_subscription_plan
      return unless plan && has_valid_wallet?

      fulfillment = UsageCredits::Fulfillment.find_by(source: self)
      return unless fulfillment # maybe they never had one?

      # We assume ends_at is set
      # If plan says expire credits on cancel or after a grace period:
      if plan.expire_credits_on_cancel
        expiry_time = ends_at
        expiry_time += plan.credit_expiration_period if plan.credit_expiration_period

        fulfillment.update!(expires_at: expiry_time)
      else
        # Or if you want to just stop awarding in the future
        fulfillment.update!(expires_at: ends_at)
      end

      # Optionally expire existing credits immediately
      # e.g. wallet.expire_credits_at(Time.current, metadata: { ... })
    end

  end
end
