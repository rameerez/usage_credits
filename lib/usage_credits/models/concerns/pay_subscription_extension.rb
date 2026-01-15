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
      after_commit :handle_plan_change_wrapper

      # TODO: handle paused subscriptions (may still have an "active" status?)
    end

    # Identify the usage_credits plan object
    # NOTE: Not memoized because processor_plan can change, and we need the current value
    def credit_subscription_plan
      UsageCredits.configuration.find_subscription_plan_by_processor_id(processor_plan)
    end

    def provides_credits?
      credit_subscription_plan.present?
    end

    def fulfillment_should_stop_at
      (ends_at || current_period_end)
    end

    private

    # Returns true if the subscription has a valid credit wallet to operate on
    def has_valid_wallet?
      return false unless customer&.owner&.respond_to?(:credit_wallet)
      return false unless customer.owner.credit_wallet.present?
      true
    end

    def credits_already_fulfilled?
      # TODO: There's a race condition where Pay actually updates the subscription two times on initial creation,
      # leading to us triggering handle_initial_award_and_fulfillment_setup twice too.
      # Since no Fulfillment record has been created yet, both callbacks will try to create the same Fulfillment object
      # at about the same time, thus making this check useless (there's nothing written to the DB yet)
      # For now, we handle it by adding a validation to the Fulfillment model so that there's no two Fulfillment objects
      # with the same source_id -- so whichever of the two callbacks gets processed first wins, the other just fails.
      # That's how we prevent double credit awarding for now, but this race condition should be handled more elegantly.
      fulfillment = UsageCredits::Fulfillment.find_by(source: self)
      return false unless fulfillment

      # A stopped fulfillment (stops_at in the past) should NOT prevent reactivation
      # This handles: credit → non-credit → credit transitions (after stop date)
      return false if fulfillment.stops_at.present? && fulfillment.stops_at <= Time.current

      # A fulfillment scheduled to stop (has stopped_reason but stops_at is in the future)
      # should also allow reactivation - user changed their mind before the stop took effect
      return false if fulfillment.metadata["stopped_reason"].present?

      true
    end

    # Returns an existing fulfillment that is stopped or scheduled to stop
    # Used for reactivation scenarios (credit → non-credit → credit)
    def reactivatable_fulfillment
      fulfillment = UsageCredits::Fulfillment.find_by(source: self)
      return nil unless fulfillment

      # Fulfillment is reactivatable if:
      # 1. stops_at is in the past (actually stopped), OR
      # 2. stopped_reason is set (scheduled to stop, but not yet)
      is_stopped = fulfillment.stops_at.present? && fulfillment.stops_at <= Time.current
      is_scheduled_to_stop = fulfillment.metadata["stopped_reason"].present?

      return nil unless is_stopped || is_scheduled_to_stop
      fulfillment
    end

    def subscription_renewed?
      (saved_change_to_ends_at? || saved_change_to_current_period_end?) && status == "active"
    end

    # This doesn't get called the exact moment the user cancels its subscription, but at the end of the period,
    # when the payment processor sends the event that the subscription has actually been cancelled.
    # For the moment the user clicks on "Cancel subscription", the sub keeps its state as "active" (for now),
    # the sub just gets its `ends_at` set from nil to the actual cancellation date.
    def subscription_canceled?
      saved_change_to_status? && status == "canceled"
    end

    def plan_changed?
      return false unless saved_change_to_processor_plan? && status == "active"

      # The old plan ID must be present (not nil) - otherwise this is initial subscription creation
      # not a plan change. Initial subscription is handled by handle_initial_award_and_fulfillment_setup.
      old_plan_id = saved_change_to_processor_plan[0]
      return false if old_plan_id.nil?

      # Only trigger plan_change if the OLD plan was a credit plan.
      # If old plan wasn't a credit plan (not in config), then handle_initial_award_and_fulfillment_setup
      # will handle the "fresh start" case - we don't want to double-award credits.
      old_plan = UsageCredits.configuration.find_subscription_plan_by_processor_id(old_plan_id)
      return false unless old_plan.present?

      # At this point, old plan provided credits. We handle:
      # - Credit → Credit (upgrade/downgrade)
      # - Credit → Non-credit (stop fulfillment)
      true
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

      # Check if we need to reactivate a stopped fulfillment (credit → non-credit → credit scenario)
      existing_reactivatable_fulfillment = reactivatable_fulfillment
      is_reactivation = existing_reactivatable_fulfillment.present?

      # Skip if we already have an ACTIVE fulfillment record
      return if credits_already_fulfilled?

      plan = credit_subscription_plan
      wallet = customer.owner.credit_wallet

      # Calculate credit expiration using the shared helper
      credits_expire_at = calculate_credit_expiration(plan, current_period_start)

      Rails.logger.info "Fulfilling #{is_reactivation ? 'reactivation' : 'initial'} credits for subscription #{id}"
      Rails.logger.info "  Status: #{status}"
      Rails.logger.info "  Plan: #{plan}"

      # Transaction for atomic awarding + fulfillment creation/reactivation
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
              reason: is_reactivation ? "reactivation_trial_credits" : "initial_trial_credits",
              plan: processor_plan,
              fulfilled_at: Time.current
            }
          )
          transaction_ids << transaction.id
          total_credits_awarded += plan.trial_credits

        elsif status == "active"

          # Awarding of signup bonus, if any (only on initial setup, not reactivation)
          if plan.signup_bonus_credits.positive? && !is_reactivation
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
                reason: is_reactivation ? "reactivation" : "first_cycle",
                plan: processor_plan,
                fulfilled_at: Time.current
              }
            )
            transaction_ids << transaction.id
            total_credits_awarded += plan.credits_per_period
          end
        end

        # 2) Create or reactivate Fulfillment record for subsequent awarding
        # Use current_period_start as the base time, falling back to Time.current
        period_start = if trial_ends_at && status == "trialing"
                      trial_ends_at
                    else
                      current_period_start || Time.current
                    end

        # Ensure next_fulfillment_at is in the future
        next_fulfillment_at = period_start + plan.parsed_fulfillment_period
        next_fulfillment_at = Time.current + plan.parsed_fulfillment_period if next_fulfillment_at <= Time.current

        if is_reactivation
          # Reactivate the existing stopped/scheduled-to-stop fulfillment
          # Merge metadata to preserve any custom keys while updating core fields
          # Use string keys consistently to avoid duplicates after JSON serialization
          existing_reactivatable_fulfillment.update!(
            credits_last_fulfillment: total_credits_awarded,
            fulfillment_period: plan.fulfillment_period_display,
            last_fulfilled_at: Time.current,
            next_fulfillment_at: next_fulfillment_at,
            stops_at: fulfillment_should_stop_at,
            metadata: existing_reactivatable_fulfillment.metadata
              .except("stopped_reason", "stopped_at", "pending_plan_change", "plan_change_at")
              .merge(
                "subscription_id" => id,
                "plan" => processor_plan,
                "reactivated_at" => Time.current
              )
          )
          fulfillment = existing_reactivatable_fulfillment

          Rails.logger.info "Reactivated fulfillment #{fulfillment.id} for subscription #{id}"
        else
          # Create new fulfillment
          # Use string keys consistently to avoid duplicates after JSON serialization
          fulfillment = UsageCredits::Fulfillment.create!(
            wallet: wallet,
            source: self,
            fulfillment_type: "subscription",
            credits_last_fulfillment: total_credits_awarded,
            fulfillment_period: plan.fulfillment_period_display,
            last_fulfilled_at: Time.current,
            next_fulfillment_at: next_fulfillment_at,
            stops_at: fulfillment_should_stop_at, # Pre-emptively set when the fulfillment will stop, in case we miss a future event (like sub cancellation)
            metadata: {
              "subscription_id" => id,
              "plan" => processor_plan,
            }
          )

          Rails.logger.info "Initial fulfillment for subscription #{id} finished. Created fulfillment #{fulfillment.id}"
        end

        # Link created transactions to the fulfillment object for traceability
        UsageCredits::Transaction.where(id: transaction_ids).update_all(fulfillment_id: fulfillment.id)

        # Dispatch subscription_credits_awarded callback if credits were actually awarded
        if total_credits_awarded > 0
          UsageCredits::Callbacks.dispatch(:subscription_credits_awarded,
            wallet: wallet,
            amount: total_credits_awarded,
            metadata: {
              subscription_plan_name: plan.name,
              subscription: plan,
              pay_subscription: self,
              fulfillment_period: plan.fulfillment_period_display,
              is_reactivation: is_reactivation,
              status: status
            }
          )
        end

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
        # Check if there's a pending plan change to apply
        if fulfillment.metadata["pending_plan_change"].present?
          apply_pending_plan_change(fulfillment)
        end

        # Subscription renewed, we can set the new Fulfillment stops_at to the extended date
        fulfillment.update!(stops_at: fulfillment_should_stop_at)
        Rails.logger.info "Fulfillment #{fulfillment.id} stops_at updated to #{fulfillment.stops_at}"
      rescue => e
        Rails.logger.error "Failed to extend fulfillment period for subscription #{id}: #{e.message}"
        raise ActiveRecord::Rollback
      end
    end


    # If the subscription is canceled, let's set the Fulfillment's stops_at so that the job won't keep awarding
    def update_fulfillment_on_cancellation
      plan = credit_subscription_plan
      return unless plan && has_valid_wallet?

      fulfillment = UsageCredits::Fulfillment.find_by(source: self)
      return unless fulfillment

      ActiveRecord::Base.transaction do
        # Subscription cancelled, so stop awarding credits in the future
        fulfillment.update!(stops_at: fulfillment_should_stop_at)
        Rails.logger.info "Fulfillment #{fulfillment.id} stops_at set to #{fulfillment.stops_at} due to cancellation"
      rescue => e
        Rails.logger.error "Failed to stop credit fulfillment for subscription #{id}: #{e.message}"
        raise ActiveRecord::Rollback
      end

      # TODO: we can also expire already awarded credits here (without making the ledger mutable – we'll need to
      # check if the plan expires credits or not, and if rollover we may need to add a negative transaction to offset
      # the remaining balance)

    end

    # Wrapper to check condition and call handle_plan_change
    def handle_plan_change_wrapper
      return unless plan_changed?
      handle_plan_change
    end

    # Handle plan changes (upgrades/downgrades)
    def handle_plan_change
      return unless has_valid_wallet?

      fulfillment = UsageCredits::Fulfillment.find_by(source: self)
      return unless fulfillment

      # Debug logging to track plan changes and potential issues
      Rails.logger.info "=" * 80
      Rails.logger.info "[UsageCredits] Plan change detected for subscription #{id}"
      Rails.logger.info "  Processor plan changed: #{saved_change_to_processor_plan.inspect}"
      Rails.logger.info "  Subscription status: #{status}"
      Rails.logger.info "  Current period end: #{current_period_end}"
      Rails.logger.info "  Fulfillment metadata: #{fulfillment.metadata.inspect}"
      Rails.logger.info "  Fulfillment period: #{fulfillment.fulfillment_period}"
      Rails.logger.info "  Next fulfillment at: #{fulfillment.next_fulfillment_at}"

      # Warn if current_period_end is nil for an active subscription - this is an edge case
      # that could indicate incomplete data from the payment processor
      if current_period_end.nil? && status == "active"
        Rails.logger.warn "Subscription #{id} is active but current_period_end is nil - using Time.current as fallback for plan change scheduling"
      end

      # Get the current active plan (what the user is ACTUALLY on right now)
      # This is crucial for handling multiple plan changes in one billing period
      current_plan_id = fulfillment.metadata["plan"]
      new_plan_id = processor_plan

      Rails.logger.info "  Looking up current plan: #{current_plan_id}"
      Rails.logger.info "  Looking up new plan: #{new_plan_id}"

      current_plan = UsageCredits.configuration.find_subscription_plan_by_processor_id(current_plan_id)
      new_plan = UsageCredits.configuration.find_subscription_plan_by_processor_id(new_plan_id)

      Rails.logger.info "  Current plan found: #{current_plan&.name} (#{current_plan&.credits_per_period} credits)"
      Rails.logger.info "  New plan found: #{new_plan&.name} (#{new_plan&.credits_per_period} credits)"

      # Handle downgrade to a non-credit plan: schedule fulfillment stop for end of period
      if new_plan.nil? && current_plan.present?
        handle_downgrade_to_non_credit_plan(fulfillment)
        return
      end

      return unless new_plan  # Neither current nor new plan provides credits - nothing to do

      ActiveRecord::Base.transaction do
        # FIRST: Check if returning to current plan (canceling a pending change)
        # This must come first! Returning to current plan = no credits, just clear pending
        # This matches Stripe's billing: no new charge means no new credits
        if current_plan_id == new_plan_id
          Rails.logger.info "  Action: Returning to current plan (clearing pending change)"
          clear_pending_plan_change(fulfillment)
          return
        end

        # Now compare credits to determine upgrade vs downgrade
        current_credits = current_plan&.credits_per_period || 0
        new_credits = new_plan.credits_per_period

        Rails.logger.info "  Comparing credits: #{current_credits} → #{new_credits}"

        if new_credits > current_credits
          # UPGRADE: Grant new plan credits immediately
          Rails.logger.info "  Action: UPGRADE detected - awarding #{new_credits} credits immediately"
          handle_plan_upgrade(new_plan, fulfillment)
        elsif new_credits < current_credits
          # DOWNGRADE: Schedule for end of period (overwrites any previous pending)
          Rails.logger.info "  Action: DOWNGRADE detected - scheduling for end of period"
          handle_plan_downgrade(new_plan, fulfillment)
        else
          # Same credits amount, different plan - update metadata immediately
          Rails.logger.info "  Action: Same credits, different plan - updating metadata only"
          update_fulfillment_plan_metadata(fulfillment, new_plan_id)
        end
      rescue => e
        Rails.logger.error "Failed to handle plan change for subscription #{id}: #{e.message}"
        Rails.logger.error e.backtrace.join("\n")
        raise ActiveRecord::Rollback
      end

      Rails.logger.info "  Plan change completed successfully"
      Rails.logger.info "=" * 80
    end

    def handle_plan_upgrade(new_plan, fulfillment)
      wallet = customer.owner.credit_wallet

      Rails.logger.info "    [UPGRADE] Starting upgrade process"
      Rails.logger.info "    [UPGRADE] Wallet ID: #{wallet.id}, Current balance: #{wallet.balance}"
      Rails.logger.info "    [UPGRADE] Credits to award: #{new_plan.credits_per_period}"
      Rails.logger.info "    [UPGRADE] New plan period: #{new_plan.fulfillment_period_display}"

      # Calculate expiration using shared helper (uses current_period_end for upgrades)
      credits_expire_at = calculate_credit_expiration(new_plan, current_period_end)

      Rails.logger.info "    [UPGRADE] Credits expire at: #{credits_expire_at || 'never (rollover enabled)'}"

      # Grant full new plan credits immediately
      # Use string keys consistently to avoid duplicates after JSON serialization
      upgrade_transaction = wallet.add_credits(
        new_plan.credits_per_period,
        category: "subscription_upgrade",
        expires_at: credits_expire_at,
        metadata: {
          "subscription_id" => id,
          "plan" => processor_plan,
          "reason" => "plan_upgrade",
          "fulfilled_at" => Time.current
        }
      )

      # Dispatch subscription_credits_awarded callback for the upgrade
      UsageCredits::Callbacks.dispatch(:subscription_credits_awarded,
        wallet: wallet,
        amount: new_plan.credits_per_period,
        transaction: upgrade_transaction,
        metadata: {
          subscription_plan_name: new_plan.name,
          subscription: new_plan,
          pay_subscription: self,
          fulfillment_period: new_plan.fulfillment_period_display,
          reason: "plan_upgrade"
        }
      )

      Rails.logger.info "    [UPGRADE] Credits awarded successfully"
      Rails.logger.info "    [UPGRADE] New balance: #{wallet.reload.balance}"

      # Calculate next fulfillment time based on the NEW plan's period
      # This ensures the fulfillment schedule matches the new plan's cadence
      next_fulfillment_at = Time.current + new_plan.parsed_fulfillment_period

      Rails.logger.info "    [UPGRADE] Updating fulfillment record"
      Rails.logger.info "    [UPGRADE] Old fulfillment_period: #{fulfillment.fulfillment_period}"
      Rails.logger.info "    [UPGRADE] New fulfillment_period: #{new_plan.fulfillment_period_display}"
      Rails.logger.info "    [UPGRADE] Old next_fulfillment_at: #{fulfillment.next_fulfillment_at}"
      Rails.logger.info "    [UPGRADE] New next_fulfillment_at: #{next_fulfillment_at}"

      # Update fulfillment with ALL new plan properties
      # This includes the period display string and the next fulfillment time
      # to ensure future fulfillments happen on the correct schedule
      # Use string keys consistently to avoid duplicates after JSON serialization
      fulfillment.update!(
        fulfillment_period: new_plan.fulfillment_period_display,
        next_fulfillment_at: next_fulfillment_at,
        metadata: fulfillment.metadata
          .except("pending_plan_change", "plan_change_at")
          .merge("plan" => processor_plan)
      )

      Rails.logger.info "    [UPGRADE] Fulfillment updated successfully"
      Rails.logger.info "Subscription #{id} upgraded to #{processor_plan}, granted #{new_plan.credits_per_period} credits"
      Rails.logger.info "  Fulfillment period updated to: #{new_plan.fulfillment_period_display}"
      Rails.logger.info "  Next fulfillment scheduled for: #{next_fulfillment_at}"
    end

    def handle_plan_downgrade(new_plan, fulfillment)
      # Schedule the downgrade for end of current period
      # User keeps current plan benefits until then
      # Ensure schedule_time is never in the past (handles edge cases like stale data)
      schedule_time = [current_period_end || Time.current, Time.current].max

      # Use string keys consistently to avoid duplicates after JSON serialization
      fulfillment.update!(
        metadata: fulfillment.metadata.merge(
          "pending_plan_change" => processor_plan,
          "plan_change_at" => schedule_time
        )
      )

      Rails.logger.info "Subscription #{id} downgrade to #{processor_plan} scheduled for #{schedule_time}"
    end

    def handle_downgrade_to_non_credit_plan(fulfillment)
      # User is downgrading from a credit plan to a non-credit plan
      # Schedule the fulfillment to stop at end of current period
      # User keeps their existing credits (no clawback)
      # Ensure schedule_time is never in the past
      schedule_time = [current_period_end || Time.current, Time.current].max

      ActiveRecord::Base.transaction do
        # Use string keys consistently to avoid duplicates after JSON serialization
        fulfillment.update!(
          stops_at: schedule_time,
          metadata: fulfillment.metadata.merge(
            "stopped_reason" => "downgrade_to_non_credit_plan",
            "stopped_at" => schedule_time
          )
        )

        Rails.logger.info "Subscription #{id} downgraded to non-credit plan #{processor_plan}, fulfillment will stop at #{schedule_time}"
      rescue => e
        Rails.logger.error "Failed to handle downgrade to non-credit plan for subscription #{id}: #{e.message}"
        Rails.logger.error e.backtrace.join("\n")
        raise ActiveRecord::Rollback
      end
    end

    def update_fulfillment_plan_metadata(fulfillment, new_plan_id)
      # Use string keys consistently to avoid duplicates after JSON serialization
      fulfillment.update!(
        metadata: fulfillment.metadata.merge("plan" => new_plan_id)
      )
    end

    # Clear any pending plan change metadata
    # Used when user upgrades back to their current plan after scheduling a downgrade
    def clear_pending_plan_change(fulfillment)
      return unless fulfillment.metadata["pending_plan_change"].present?

      fulfillment.update!(
        metadata: fulfillment.metadata.except("pending_plan_change", "plan_change_at")
      )

      Rails.logger.info "Subscription #{id} pending plan change cleared (returned to current plan)"
    end

    def apply_pending_plan_change(fulfillment)
      pending_plan = fulfillment.metadata["pending_plan_change"]

      # Validate that the pending plan still exists in configuration
      # This handles the edge case where an admin removes a plan after a user scheduled a downgrade
      unless UsageCredits.configuration.find_subscription_plan_by_processor_id(pending_plan)
        Rails.logger.error "Cannot apply pending plan change for subscription #{id}: plan '#{pending_plan}' not found in configuration"
        # Clear the invalid pending change to prevent repeated failures
        fulfillment.update!(
          metadata: fulfillment.metadata.except("pending_plan_change", "plan_change_at")
        )
        return
      end

      # Update to the new plan and clear the pending change
      # Use string keys consistently to avoid duplicates after JSON serialization
      fulfillment.update!(
        metadata: fulfillment.metadata
          .except("pending_plan_change", "plan_change_at")
          .merge("plan" => pending_plan)
      )

      Rails.logger.info "Applied pending plan change for subscription #{id}: now on #{pending_plan}"
    end

    # =========================================
    # Helper Methods
    # =========================================

    # Calculate credit expiration date for a given plan
    # Handles the edge case where base_time might be in the past (e.g., paused subscription reactivated)
    # by ensuring we never create credits that are already expired
    def calculate_credit_expiration(plan, base_time = nil)
      return nil if plan.rollover_enabled

      # Use the provided base_time or fall back to current time
      # Crucially: ensure we never use a time in the past, which would create already-expired credits
      # This fixes the bug where a paused subscription reactivated would have past expiration dates
      effective_base = [base_time || Time.current, Time.current].max

      # Cap the grace period to the fulfillment period to prevent balance accumulation
      # when fulfillment_period << grace_period (e.g., 15 seconds vs 5 minutes)
      fulfillment_period = plan.parsed_fulfillment_period
      effective_grace = [
        UsageCredits.configuration.fulfillment_grace_period,
        fulfillment_period
      ].min

      effective_base + fulfillment_period + effective_grace
    end

  end
end
