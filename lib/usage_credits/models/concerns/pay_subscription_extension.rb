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
      after_commit :handle_initial_award_and_fulfillment_setup, on: [:create, :update]

      after_commit :update_fulfillment_on_renewal, on: :update, if: :subscription_renewed?
      after_commit :update_fulfillment_on_cancellation, on: :update, if: :subscription_canceled?
      after_commit :handle_plan_change_wrapper, on: :update
      after_commit :apply_deferred_plan_change_after_resume, on: :update
    end

    # Identify the usage_credits plan object
    # NOTE: Not memoized because processor_plan can change, and we need the current value
    def credit_subscription_plan
      UsageCredits.configuration.find_subscription_plan_by_processor_id(processor_plan)
    end

    def provides_credits?
      subscription_terms.present?
    end

    def fulfillment_should_stop_at
      ends_at || current_period_end
    end

    # Pay's processor-specific #active? implementation is the source of truth
    # for grace periods and effective pauses. Pay::Subscription itself does not
    # implement #paused?, however, so legacy/base-class rows need the equivalent
    # lifecycle check without calling Pay's otherwise unsafe base #active?.
    # In particular, Stripe keeps the raw status as "active" while a void pause
    # is in effect.
    def eligible_for_usage_credit_fulfillment?(include_trial: false)
      processor_active = if status == "on_trial"
        respond_to?(:on_trial?) && on_trial?
      elsif respond_to?(:paused?)
        active?
      else
        ["trialing", "active"].include?(status) && !ended?
      end

      return false unless processor_active
      return false if paused_for_usage_credits?

      include_trial || !trialing_for_credits?
    end

    # Reconcile the initial/trial award state on demand. The recurring service
    # uses this at lifecycle boundaries for processors (notably Braintree,
    # whose status can remain `active` throughout a trial) and to finish a
    # deferred plan change before any recurring credits can be minted.
    def sync_usage_credit_fulfillment!
      handle_initial_award_and_fulfillment_setup
      apply_deferred_plan_change_after_resume
    end

    private

    # Returns true if the subscription has a valid credit wallet to operate on
    def has_valid_wallet?
      return false unless customer&.owner&.respond_to?(:credit_wallet)
      return false unless customer.owner.credit_wallet.present?
      true
    end

    def credits_already_fulfilled?
      fulfillment = UsageCredits::Fulfillment.find_by(source: self)
      return false unless fulfillment

      # Deferred terms own resume reconciliation. Treat the fulfillment as
      # initialized until those terms are atomically installed so the generic
      # reactivation path cannot mint an unintended extra first cycle.
      return true if fulfillment.metadata.key?("deferred_plan_change")

      # A stopped fulfillment (stops_at in the past) should NOT prevent reactivation
      # This handles: credit → non-credit → credit transitions (after stop date)
      return false if fulfillment.stops_at.present? && fulfillment.stops_at <= Time.current

      # A fulfillment scheduled to stop (has stopped_reason but stops_at is in the future)
      # should also allow reactivation - user changed their mind before the stop took effect
      return false if fulfillment.metadata["stopped_reason"].present?

      initial_award_completed?(fulfillment)
    end

    def initial_award_completed?(fulfillment)
      award_state = fulfillment.metadata["initial_award_state"]

      if trialing_for_credits?
        # Any existing trial/active initial award makes a trial callback
        # idempotent. Active subscriptions never move backwards into trial.
        true
      elsif status == "active"
        return true if award_state == "active"
        return false if award_state == "trial" || fulfillment.metadata["trial"]

        # Pre-1.0 fulfillments do not carry initial_award_state. Conservatively
        # treat a non-trial legacy row as already active to avoid over-crediting
        # existing customers during upgrade.
        true
      else
        false
      end
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
      (saved_change_to_ends_at? || saved_change_to_current_period_end?) &&
        eligible_for_usage_credit_fulfillment?
    end

    # This doesn't get called the exact moment the user cancels its subscription, but at the end of the period,
    # when the payment processor sends the event that the subscription has actually been cancelled.
    # For the moment the user clicks on "Cancel subscription", the sub keeps its state as "active" (for now),
    # the sub just gets its `ends_at` set from nil to the actual cancellation date.
    def subscription_canceled?
      saved_change_to_status? && status == "canceled"
    end

    def plan_changed?
      return false unless saved_change_to_processor_plan?
      return false unless eligible_for_usage_credit_fulfillment? || paused_for_usage_credits?

      # The old plan ID must be present (not nil) - otherwise this is initial subscription creation
      # not a plan change. Initial subscription is handled by handle_initial_award_and_fulfillment_setup.
      old_plan_id = saved_change_to_processor_plan[0]
      return false if old_plan_id.nil?

      # Only trigger plan_change if the OLD plan was a credit plan.
      # If old plan wasn't a credit plan (not in config), then handle_initial_award_and_fulfillment_setup
      # will handle the "fresh start" case - we don't want to double-award credits.
      old_plan = UsageCredits.configuration.find_subscription_plan_by_processor_id(old_plan_id)
      fulfillment = UsageCredits::Fulfillment.find_by(source: self)
      return false unless old_plan.present? || fulfillment.present?

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
      plan = subscription_terms
      return unless plan
      return unless has_valid_wallet?

      # Pay normalizes trials and pauses differently per processor. Trust its
      # active predicate instead of the raw status, which remains "active" for
      # an effective Stripe void pause.
      return unless eligible_for_usage_credit_fulfillment?(include_trial: true)

      # Skip if we already have an ACTIVE fulfillment record
      return if credits_already_fulfilled?

      wallet = customer.owner.credit_wallet

      # Calculate credit expiration using the shared helper
      credits_expire_at = calculate_credit_expiration(plan, current_period_start)

      # Variables to track for callback dispatch after transaction commits
      total_credits_awarded = 0
      last_credit_transaction = nil
      is_reactivation = false

      # Transaction for atomic awarding + fulfillment creation/reactivation
      # Callback is dispatched AFTER this block to ensure credits are persisted
      self.class.transaction do
        # Lock order for every subscription mutation is subscription →
        # fulfillment → wallet. Serializing on the Pay row closes duplicate
        # webhook races and prevents lock-order deadlocks with recurring jobs.
        return unless lock_current_subscription_version
        return unless eligible_for_usage_credit_fulfillment?(include_trial: true)
        existing_fulfillment = UsageCredits::Fulfillment.lock.find_by(source: self)
        wallet.lock!
        return if existing_fulfillment&.metadata&.key?("deferred_plan_change")
        return if existing_fulfillment && initial_award_completed?(existing_fulfillment) && !reactivatable_record?(existing_fulfillment)

        is_reactivation = existing_fulfillment.present? && reactivatable_record?(existing_fulfillment)
        is_trial_activation = existing_fulfillment.present? && status == "active" && !trialing_for_credits? && !is_reactivation

        Rails.logger.info "Fulfilling #{is_reactivation ? "reactivation" : "initial"} credits for subscription #{id}"
        Rails.logger.info "  Status: #{status}"
        Rails.logger.info "  Plan: #{plan}"

        # Create or reactivate the fulfillment before minting so every ledger
        # row is linked at INSERT time. The enclosing transaction keeps the
        # temporary zero amount invisible and rolls everything back together.
        fulfilled_at = Time.current
        next_fulfillment_at = next_subscription_fulfillment_at(plan)
        award_state = trialing_for_credits? ? "trial" : "active"

        fulfillment_record = if is_reactivation || is_trial_activation
          existing_fulfillment.tap do |record|
            record.update!(
              credits_last_fulfillment: 0,
              fulfillment_period: plan.fulfillment_period_display,
              last_fulfilled_at: fulfilled_at,
              next_fulfillment_at: next_fulfillment_at,
              stops_at: fulfillment_should_stop_at,
              metadata: record.metadata
                .except(
                  "trial", "stopped_reason", "stopped_at", "stopped_plan",
                  "pending_plan_change", "pending_plan_snapshot", "plan_change_at"
                )
                .merge(plan_snapshot_metadata(plan))
                .merge(
                  "subscription_id" => id,
                  "initial_award_state" => award_state,
                  (is_reactivation ? "reactivated_at" : "activated_at") => fulfilled_at
                )
            )
          end
        else
          UsageCredits::Fulfillment.create!(
            wallet: wallet,
            source: self,
            fulfillment_type: "subscription",
            credits_last_fulfillment: 0,
            fulfillment_period: plan.fulfillment_period_display,
            last_fulfilled_at: fulfilled_at,
            next_fulfillment_at: next_fulfillment_at,
            stops_at: fulfillment_should_stop_at,
            metadata: {
              "subscription_id" => id,
              "initial_award_state" => award_state,
              "trial" => trialing_for_credits?
            }.merge(plan_snapshot_metadata(plan))
          )
        end

        # If this is a trial and not an active subscription, award trial credits.
        if trialing_for_credits? && plan.trial_credits.positive?
          last_credit_transaction = wallet.add_credits(plan.trial_credits,
            category: "subscription_trial",
            expires_at: trial_ends_at,
            fulfillment: fulfillment_record,
            metadata: {
              subscription_id: id,
              reason: is_reactivation ? "reactivation_trial_credits" : "initial_trial_credits",
              plan: processor_plan,
              fulfilled_at: fulfilled_at
            })
          total_credits_awarded += plan.trial_credits
        elsif status == "active"
          # Awarding of signup bonus, if any (only on initial setup, not reactivation)
          if plan.signup_bonus_credits.positive? && !is_reactivation
            bonus_transaction = wallet.add_credits(plan.signup_bonus_credits,
              category: "subscription_signup_bonus",
              fulfillment: fulfillment_record,
              metadata: {
                subscription_id: id,
                reason: "signup_bonus",
                plan: processor_plan,
                fulfilled_at: fulfilled_at
              })
            total_credits_awarded += plan.signup_bonus_credits
            last_credit_transaction = bonus_transaction
          end

          # Actual awarding of the subscription credits
          if plan.credits_per_period.positive?
            credits_transaction = wallet.add_credits(plan.credits_per_period,
              category: "subscription_credits",
              expires_at: credits_expire_at,
              fulfillment: fulfillment_record,
              metadata: {
                subscription_id: id,
                reason: is_reactivation ? "reactivation" : "first_cycle",
                plan: processor_plan,
                fulfilled_at: fulfilled_at
              })
            total_credits_awarded += plan.credits_per_period
            last_credit_transaction = credits_transaction
          end
        end

        fulfillment_record.update!(credits_last_fulfillment: total_credits_awarded)
        Rails.logger.info "Fulfillment #{fulfillment_record.id} updated for subscription #{id}"
      end

      # Dispatch callback AFTER transaction commits - ensures credits are persisted
      if total_credits_awarded > 0
        ActiveRecord.after_all_transactions_commit do
          UsageCredits::Callbacks.dispatch(:subscription_credits_awarded,
            wallet: wallet,
            amount: total_credits_awarded,
            transaction: last_credit_transaction,
            metadata: {
              subscription_plan_name: plan.name,
              subscription: plan.callback_plan,
              pay_subscription: self,
              fulfillment_period: plan.fulfillment_period_display,
              is_reactivation: is_reactivation,
              status: status
            })
        end
      end
    rescue => e
      Rails.logger.error "Failed to fulfill initial credits for subscription #{id}: #{e.message}"
      raise
    end

    def reactivatable_record?(fulfillment)
      (fulfillment.stops_at.present? && fulfillment.stops_at <= Time.current) ||
        fulfillment.metadata["stopped_reason"].present?
    end

    def next_subscription_fulfillment_at(plan)
      # Trial credits hand off at the actual processor trial boundary. Once
      # active, credit cadence is intentionally independent of billing cadence
      # (for example a monthly charge can grant credits daily).
      trial_boundary = trial_ends_at || current_period_end
      return trial_boundary if trialing_for_credits? && trial_boundary.present? && trial_boundary > Time.current

      period_start = [current_period_start || Time.current, Time.current].max
      candidate = period_start + plan.parsed_fulfillment_period
      (candidate > Time.current) ? candidate : Time.current + plan.parsed_fulfillment_period
    end

    # Handle subscription renewal (we received a new payment for another billing period)
    # Each time the subscription renews and ends_at moves forward,
    # we keep awarding credits because Fulfillment#stops_at also moves forward
    def update_fulfillment_on_renewal
      return unless has_valid_wallet?

      fulfillment = UsageCredits::Fulfillment.find_by(source: self)
      return unless fulfillment

      self.class.transaction do
        return unless lock_current_subscription_version
        fulfillment.lock!
        # Check if there's a pending plan change to apply
        if fulfillment.metadata["pending_plan_change"].present?
          apply_pending_plan_change(fulfillment)
        end

        # Subscription renewed, we can set the new Fulfillment stops_at to the extended date
        fulfillment.update!(stops_at: fulfillment_should_stop_at)
        Rails.logger.info "Fulfillment #{fulfillment.id} stops_at updated to #{fulfillment.stops_at}"
      rescue => e
        Rails.logger.error "Failed to extend fulfillment period for subscription #{id}: #{e.message}"
        raise
      end
    end

    # If the subscription is canceled, let's set the Fulfillment's stops_at so that the job won't keep awarding
    def update_fulfillment_on_cancellation
      return unless has_valid_wallet?

      fulfillment = UsageCredits::Fulfillment.find_by(source: self)
      return unless fulfillment

      self.class.transaction do
        return unless lock_current_subscription_version
        fulfillment.lock!
        wallet = fulfillment.wallet
        wallet.lock!

        active_plan_id = fulfillment.metadata["plan"]
        configured_plan = UsageCredits.configuration.find_subscription_plan_by_processor_id(active_plan_id)
        terms = terms_from_fulfillment(
          fulfillment,
          expected_plan_id: active_plan_id,
          configured_plan: configured_plan
        ) || UsageCredits::SubscriptionTerms.from_plan(configured_plan, processor_plan_id: active_plan_id)

        # Subscription cancelled, so stop awarding credits in the future
        fulfillment_attributes = {stops_at: fulfillment_should_stop_at}
        if terms&.expire_credits_on_cancel
          expires_at = cancellation_credit_expiration_at(terms)
          expire_fulfillment_credits!(wallet, fulfillment, expires_at)
          fulfillment_attributes[:metadata] = fulfillment.metadata.merge(
            "cancellation_credit_expiration_at" => expires_at,
            "cancellation_credit_expiration_applied_at" => Time.current
          )
        end

        fulfillment.update!(fulfillment_attributes)
        Rails.logger.info "Fulfillment #{fulfillment.id} stops_at set to #{fulfillment.stops_at} due to cancellation"
      rescue => e
        Rails.logger.error "Failed to stop credit fulfillment for subscription #{id}: #{e.message}"
        raise
      end
    end

    def cancellation_credit_expiration_at(terms)
      effective_cancellation_at = fulfillment_should_stop_at || Time.current
      effective_cancellation_at + terms.credit_expiration_period_seconds.seconds
    end

    def expire_fulfillment_credits!(wallet, fulfillment, expires_at)
      transactions = wallet.transactions.credits.where(fulfillment: fulfillment)
      expiry = transactions.klass.arel_table[:expires_at]
      transactions
        .where(expiry.eq(nil).or(expiry.gt(expires_at)))
        .update_all(expires_at: expires_at, updated_at: Time.current)

      # Keep the persisted cache aligned for consumers that query the column
      # directly. The public balance is still derived from ledger rows.
      wallet.send(:refresh_cached_balance!)
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

      current_plan = terms_from_fulfillment(fulfillment, expected_plan_id: current_plan_id) ||
        terms_from_config(current_plan_id)
      new_plan = UsageCredits.configuration.find_subscription_plan_by_processor_id(new_plan_id)

      Rails.logger.info "  Current plan found: #{current_plan&.name} (#{current_plan&.credits_per_period} credits)"
      Rails.logger.info "  New plan found: #{new_plan&.name} (#{new_plan&.credits_per_period} credits)"

      # A processor can change plans while service is paused. Persist the new
      # immutable terms, but never mint an upgrade until service resumes. A
      # later resume callback atomically installs the deferred terms; the next
      # normal fulfillment then uses them.
      if paused_for_usage_credits?
        defer_plan_change_until_resume(fulfillment, new_plan)
        return
      end

      # Handle downgrade to a non-credit plan: schedule fulfillment stop for end of period
      if new_plan.nil? && current_plan_id.present?
        handle_downgrade_to_non_credit_plan(fulfillment)
        return
      end

      return unless new_plan  # Neither current nor new plan provides credits - nothing to do

      self.class.transaction do
        return unless lock_current_subscription_version
        return unless eligible_for_usage_credit_fulfillment?
        fulfillment.lock!
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
          update_fulfillment_plan_metadata(fulfillment, new_plan)
        end
      rescue => e
        Rails.logger.error "Failed to handle plan change for subscription #{id}: #{e.message}"
        Rails.logger.error e.backtrace.join("\n")
        raise
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
      credits_expire_at = calculate_credit_expiration(new_plan, Time.current)

      Rails.logger.info "    [UPGRADE] Credits expire at: #{credits_expire_at || "never (rollover enabled)"}"

      # Calculate next fulfillment time based on the NEW plan's period
      # This ensures the fulfillment schedule matches the new plan's cadence
      next_fulfillment_at = Time.current + new_plan.parsed_fulfillment_period

      # Wrap all database operations in a transaction to ensure atomicity
      # The callback should only fire after ALL operations succeed
      upgrade_transaction = nil

      fulfillment.class.transaction do
        # Grant full new plan credits immediately
        # Use string keys consistently to avoid duplicates after JSON serialization
        upgrade_transaction = wallet.add_credits(
          new_plan.credits_per_period,
          category: "subscription_upgrade",
          expires_at: credits_expire_at,
          fulfillment: fulfillment,
          metadata: {
            "subscription_id" => id,
            "plan" => processor_plan,
            "reason" => "plan_upgrade",
            "fulfilled_at" => Time.current
          }
        )

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
          credits_last_fulfillment: new_plan.credits_per_period,
          last_fulfilled_at: Time.current,
          fulfillment_period: new_plan.fulfillment_period_display,
          next_fulfillment_at: next_fulfillment_at,
          metadata: fulfillment.metadata
            .except("pending_plan_change", "pending_plan_snapshot", "plan_change_at")
            .merge(plan_snapshot_metadata(new_plan))
        )
      end

      # Dispatch callback AFTER transaction commits - ensures credits are persisted
      ActiveRecord.after_all_transactions_commit do
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
          })
      end

      Rails.logger.info "    [UPGRADE] Credits awarded successfully"
      Rails.logger.info "    [UPGRADE] New balance: #{wallet.reload.balance}"
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
          "pending_plan_snapshot" => plan_snapshot_metadata(new_plan),
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

      self.class.transaction do
        return unless lock_current_subscription_version
        fulfillment.lock!
        # Use string keys consistently to avoid duplicates after JSON serialization
        fulfillment.update!(
          stops_at: schedule_time,
          metadata: fulfillment.metadata.merge(
            "stopped_reason" => "downgrade_to_non_credit_plan",
            "stopped_at" => schedule_time,
            "stopped_plan" => processor_plan
          )
        )

        Rails.logger.info "Subscription #{id} downgraded to non-credit plan #{processor_plan}, fulfillment will stop at #{schedule_time}"
      rescue => e
        Rails.logger.error "Failed to handle downgrade to non-credit plan for subscription #{id}: #{e.message}"
        Rails.logger.error e.backtrace.join("\n")
        raise
      end
    end

    def update_fulfillment_plan_metadata(fulfillment, new_plan)
      attributes = {
        metadata: fulfillment.metadata.merge(plan_snapshot_metadata(new_plan))
      }

      if fulfillment.fulfillment_period != new_plan.fulfillment_period_display
        attributes[:fulfillment_period] = new_plan.fulfillment_period_display
        attributes[:next_fulfillment_at] = Time.current + new_plan.parsed_fulfillment_period
      end

      fulfillment.update!(attributes)
    end

    # Clear any pending plan change metadata
    # Used when user upgrades back to their current plan after scheduling a downgrade
    def clear_pending_plan_change(fulfillment)
      return unless fulfillment.metadata["pending_plan_change"].present?

      fulfillment.update!(
        metadata: fulfillment.metadata.except("pending_plan_change", "pending_plan_snapshot", "plan_change_at")
      )

      Rails.logger.info "Subscription #{id} pending plan change cleared (returned to current plan)"
    end

    def defer_plan_change_until_resume(fulfillment, new_plan)
      self.class.transaction do
        return unless lock_current_subscription_version
        return unless paused_for_usage_credits?
        fulfillment.lock!

        if new_plan.nil?
          fulfillment.update!(
            stops_at: Time.current,
            metadata: fulfillment.metadata
              .except("deferred_plan_change", "deferred_plan_snapshot")
              .merge(
                "stopped_reason" => "paused_change_to_non_credit_plan",
                "stopped_at" => Time.current,
                "stopped_plan" => processor_plan
              )
          )
        elsif fulfillment.metadata["plan"] == processor_plan && !reactivatable_record?(fulfillment)
          fulfillment.update!(
            metadata: fulfillment.metadata.except("deferred_plan_change", "deferred_plan_snapshot")
          )
        else
          fulfillment.update!(
            metadata: fulfillment.metadata.merge(
              "deferred_plan_change" => processor_plan,
              "deferred_plan_snapshot" => plan_snapshot_metadata(new_plan)
            )
          )
        end
      end
    end

    def apply_deferred_plan_change_after_resume
      return unless eligible_for_usage_credit_fulfillment?

      fulfillment = UsageCredits::Fulfillment.find_by(source: self)
      return unless fulfillment&.metadata&.key?("deferred_plan_change")

      self.class.transaction do
        return unless lock_current_subscription_version
        return unless eligible_for_usage_credit_fulfillment?
        fulfillment.lock!

        plan_id = fulfillment.metadata["deferred_plan_change"]
        snapshot = fulfillment.metadata["deferred_plan_snapshot"]
        unless plan_id.to_s == processor_plan.to_s && snapshot&.fetch("plan", nil).to_s == plan_id.to_s
          raise UsageCredits::InvalidOperation,
            "Deferred plan terms for Pay::Subscription #{id} do not match its current processor plan"
        end

        fulfillment.update!(
          stops_at: fulfillment_should_stop_at,
          fulfillment_period: snapshot.fetch("fulfillment_period"),
          metadata: fulfillment.metadata
            .except(
              "deferred_plan_change",
              "deferred_plan_snapshot",
              "pending_plan_change",
              "pending_plan_snapshot",
              "plan_change_at",
              "stopped_reason",
              "stopped_at",
              "stopped_plan"
            )
            .merge(snapshot)
        )
      end
    end

    def apply_pending_plan_change(fulfillment)
      pending_plan = fulfillment.metadata["pending_plan_change"]
      pending_snapshot = fulfillment.metadata["pending_plan_snapshot"]
      pending_snapshot = nil unless pending_snapshot&.fetch("plan", nil) == pending_plan
      configured_plan = UsageCredits.configuration.find_subscription_plan_by_processor_id(pending_plan)

      # Validate that the pending plan still exists in configuration
      # This handles the edge case where an admin removes a plan after a user scheduled a downgrade
      unless configured_plan || pending_snapshot.present?
        Rails.logger.error "Cannot apply pending plan change for subscription #{id}: plan '#{pending_plan}' not found in configuration"
        # Clear the invalid pending change to prevent repeated failures
        fulfillment.update!(
          metadata: fulfillment.metadata.except("pending_plan_change", "pending_plan_snapshot", "plan_change_at")
        )
        return
      end

      snapshot = pending_snapshot.presence || plan_snapshot_metadata(configured_plan, plan_id: pending_plan)
      period = snapshot.fetch("fulfillment_period")

      # Update all cadence and quantity fields, not only the display metadata.
      fulfillment.update!(
        fulfillment_period: period,
        next_fulfillment_at: Time.current + UsageCredits::PeriodParser.parse_persisted_period(period),
        metadata: fulfillment.metadata
          .except("pending_plan_change", "pending_plan_snapshot", "plan_change_at")
          .merge(snapshot)
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

    def lock_current_subscription_version
      current = self.class.lock.find_by(id: id)
      return false unless current

      %i[
        updated_at status processor_plan current_period_start current_period_end
        trial_ends_at ends_at pause_starts_at pause_behavior pause_resumes_at metadata
      ].all? do |attribute|
        !has_attribute?(attribute) || database_equivalent_attribute?(
          attribute,
          current.public_send(attribute),
          public_send(attribute)
        )
      end
    end

    # Processor timestamps can carry nanoseconds while Rails' timestamp
    # columns persist microseconds. Comparing the raw callback object against
    # the locked row would therefore reject the exact state that was just
    # saved on adapters/platforms that leave the extra nanoseconds in memory.
    # Preserve strict comparisons for every non-temporal value, and compare
    # temporal values at the column's effective database precision.
    def database_equivalent_attribute?(attribute, persisted_value, callback_value)
      return true if persisted_value == callback_value

      type = self.class.type_for_attribute(attribute.to_s)
      return false unless [:datetime, :time].include?(type.type)
      return false if persisted_value.nil? || callback_value.nil?

      column_precision = self.class.columns_hash.fetch(attribute.to_s).precision
      precision = (column_precision || 6).clamp(0, 9)
      scale = 10**precision

      (persisted_value.to_r * scale).floor == (callback_value.to_r * scale).floor
    end

    def paused_for_usage_credits?
      return true if status == "paused"

      pause_started = respond_to?(:pause_starts_at) && pause_starts_at.present? && pause_starts_at <= Time.current
      return true if pause_started

      respond_to?(:paused?) && paused? &&
        (!respond_to?(:on_grace_period?) || !on_grace_period?)
    end

    def trialing_for_credits?
      return true if ["on_trial", "trialing"].include?(status)

      transitioned_to_active = saved_change_to_status? && ["on_trial", "trialing"].include?(status_before_last_save)
      return false if transitioned_to_active
      return on_trial? if respond_to?(:on_trial?)

      false
    end

    def plan_snapshot_metadata(plan, plan_id: processor_plan)
      cancellation_expiration_seconds =
        if plan.respond_to?(:credit_expiration_period_seconds)
          plan.credit_expiration_period_seconds
        else
          plan.credit_expiration_period&.to_i || 0
        end

      {
        "plan" => plan_id,
        "plan_name" => plan.name,
        "credits_per_period" => plan.credits_per_period,
        "signup_bonus_credits" => plan.signup_bonus_credits,
        "trial_credits" => plan.trial_credits,
        "fulfillment_period" => plan.fulfillment_period_display,
        "rollover_enabled" => plan.rollover_enabled,
        "expire_credits_on_cancel" => plan.expire_credits_on_cancel,
        "credit_expiration_period" => cancellation_expiration_seconds
      }
    end

    def subscription_terms
      configured_plan = credit_subscription_plan
      fulfillment = UsageCredits::Fulfillment.find_by(source: self)

      terms = terms_from_fulfillment(fulfillment, expected_plan_id: processor_plan, configured_plan: configured_plan)
      return terms if terms

      data = (metadata || {}).with_indifferent_access
      metadata_plan = data[:processor_plan].presence
      if data[:purchase_type] == "credit_subscription" && (metadata_plan.nil? || metadata_plan.to_s == processor_plan.to_s)
        terms = terms_from_metadata(data, configured_plan: configured_plan)
        return terms if terms
      end

      UsageCredits::SubscriptionTerms.from_plan(configured_plan, processor_plan_id: processor_plan)
    end

    def terms_from_fulfillment(fulfillment, expected_plan_id:, configured_plan: nil)
      return unless fulfillment&.fulfillment_type == "subscription"
      return unless fulfillment.metadata["plan"].to_s == expected_plan_id.to_s

      terms_from_metadata(fulfillment.metadata, configured_plan: configured_plan, processor_plan_id: expected_plan_id)
    end

    def terms_from_config(plan_id)
      plan = UsageCredits.configuration.find_subscription_plan_by_processor_id(plan_id)
      UsageCredits::SubscriptionTerms.from_plan(plan, processor_plan_id: plan_id)
    end

    def terms_from_metadata(data, configured_plan:, processor_plan_id: processor_plan)
      UsageCredits::SubscriptionTerms.from_metadata(
        data,
        processor_plan_id: processor_plan_id,
        configured_plan: configured_plan
      )
    rescue ArgumentError => e
      Rails.logger.error "Invalid subscription terms for Pay::Subscription #{id}: #{e.message}"
      nil
    end
  end
end
