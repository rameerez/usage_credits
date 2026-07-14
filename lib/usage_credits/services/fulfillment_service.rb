# lib/usage_credits/services/fulfillment_service.rb
module UsageCredits
  class FulfillmentService
    def self.process_pending_fulfillments
      count = 0
      failed = 0

      Fulfillment.due_for_fulfillment.find_each do |fulfillment|
        count += 1 if new(fulfillment).process
      rescue => e
        failed += 1
        Rails.logger.error "Failed to process fulfillment #{fulfillment.id}: #{e.message}"
        Rails.logger.error e.backtrace.join("\n")
        next # Continue with next fulfillment
      end

      Rails.logger.info "Processed #{count} fulfillments (#{failed} failed)"
      count
    end

    def initialize(fulfillment)
      @fulfillment = fulfillment
      validate_fulfillment!
    end

    def process
      credit_transaction = nil

      reconcile_subscription_source!

      @fulfillment.class.transaction do
        lock_subscription_source!
        @fulfillment.lock! # row lock to avoid double awarding

        # re-check if it's still due, in case time changed or another process already updated it
        next unless @fulfillment.due_for_fulfillment?
        next unless subscription_source_eligible?

        credits = calculate_credits
        unless credits.is_a?(Integer) && credits.positive?
          raise UsageCredits::Error, "Fulfillment credits must be a positive whole number"
        end

        credit_transaction = give_credits(credits)
        update_fulfillment(credits)
      end

      dispatch_subscription_callback(credit_transaction) if credit_transaction
      credit_transaction
    rescue UsageCredits::Error => e
      Rails.logger.error "Usage credits error processing fulfillment #{@fulfillment.id}: #{e.message}"
      raise
    rescue => e
      Rails.logger.error "Unexpected error processing fulfillment #{@fulfillment.id}: #{e.message}"
      raise
    end

    private

    def reconcile_subscription_source!
      return unless @fulfillment.fulfillment_type == "subscription"
      return unless @fulfillment.metadata["initial_award_state"] == "trial" ||
        @fulfillment.metadata.key?("deferred_plan_change")

      source = @fulfillment.source
      return unless source.is_a?(Pay::Subscription)
      return unless source.eligible_for_usage_credit_fulfillment?

      source.sync_usage_credit_fulfillment!
      @fulfillment.reload
    end

    def lock_subscription_source!
      @pay_subscription_source = false
      @locked_subscription_source = nil
      return unless @fulfillment.fulfillment_type == "subscription"

      # A persisted polymorphic type means this fulfillment was explicitly
      # tied to Pay. Do not reinterpret a dangling reference as a legacy
      # source-less/custom subscription and continue minting credits.
      source_class = @fulfillment.source_type&.safe_constantize
      @pay_subscription_source = source_class && source_class <= Pay::Subscription
      source = @fulfillment.source
      return unless @pay_subscription_source || source.is_a?(Pay::Subscription)

      unless source
        raise UsageCredits::Error,
          "Pay subscription #{@fulfillment.source_id} for fulfillment #{@fulfillment.id} no longer exists"
      end

      # All subscription writers use subscription → fulfillment → wallet lock
      # order. Taking the processor row first makes the status check and credit
      # mint linearizable with cancellation/activation webhooks.
      @pay_subscription_source = true
      @locked_subscription_source = source.class.lock.find_by(id: source.id)
      unless @locked_subscription_source
        raise UsageCredits::Error,
          "Pay subscription #{source.id} for fulfillment #{@fulfillment.id} no longer exists"
      end
    end

    def subscription_source_eligible?
      return true unless @fulfillment.fulfillment_type == "subscription"
      return true unless @pay_subscription_source

      # A stale/delayed job must never keep minting recurring credits while the
      # processor subscription is trialing, canceled, paused, or incomplete.
      # Pay's processor-specific predicate handles Stripe pauses whose raw
      # status remains "active" until the subscription is resumed.
      source = @locked_subscription_source
      return false unless source&.eligible_for_usage_credit_fulfillment?

      if @fulfillment.metadata.key?("deferred_plan_change")
        raise UsageCredits::InvalidOperation,
          "Deferred plan change for fulfillment #{@fulfillment.id} was not reconciled"
      end

      source_plan = source.processor_plan.to_s
      active_plan = @fulfillment.metadata["plan"].to_s
      resolved_transition = source_plan == active_plan ||
        @fulfillment.metadata["pending_plan_change"].to_s == source_plan ||
        @fulfillment.metadata["stopped_plan"].to_s == source_plan

      unless resolved_transition
        raise UsageCredits::InvalidOperation,
          "Pay subscription #{source.id} plan transition has not been reconciled for fulfillment #{@fulfillment.id}"
      end

      true
    end

    def validate_fulfillment!
      raise UsageCredits::Error, "No fulfillment provided" if @fulfillment.nil?
      raise UsageCredits::Error, "Invalid fulfillment type" unless ["subscription", "credit_pack", "manual"].include?(@fulfillment.fulfillment_type)
      raise UsageCredits::Error, "No wallet associated with fulfillment" if @fulfillment.wallet.nil?

      # Validate required metadata based on type
      case @fulfillment.fulfillment_type
      when "subscription"
        raise UsageCredits::Error, "No plan specified in metadata" unless @fulfillment.metadata["plan"].present?
      when "credit_pack"
        pack_name = @fulfillment.metadata["pack"] || @fulfillment.metadata["pack_name"]
        raise UsageCredits::Error, "No pack specified in metadata" unless pack_name.present?
      else
        raise UsageCredits::Error, "No credits amount specified in metadata" unless @fulfillment.metadata["credits"].present?
      end
    end

    def give_credits(credits)
      @fulfillment.wallet.add_credits(
        credits,
        category: fulfillment_category,
        metadata: fulfillment_metadata,
        expires_at: calculate_expiration, # Will be nil if rollover is enabled
        fulfillment: @fulfillment
      )
    end

    def dispatch_subscription_callback(transaction)
      return unless @fulfillment.fulfillment_type == "subscription"

      ActiveRecord.after_all_transactions_commit do
        UsageCredits::Callbacks.dispatch(
          :subscription_credits_awarded,
          wallet: @fulfillment.wallet,
          amount: transaction.amount,
          transaction: transaction,
          metadata: {
            fulfillment: @fulfillment,
            subscription_plan_name: @plan&.name,
            pay_subscription: @fulfillment.source,
            fulfillment_period: @fulfillment.fulfillment_period,
            reason: "fulfillment_cycle"
          }
        )
      end
    end

    def update_fulfillment(credits)
      @fulfillment.update!(
        last_fulfilled_at: Time.current,
        credits_last_fulfillment: credits,
        next_fulfillment_at: @fulfillment.calculate_next_fulfillment
      )
    end

    def calculate_credits
      case @fulfillment.fulfillment_type
      when "subscription"
        @plan = UsageCredits.find_subscription_plan_by_processor_id(@fulfillment.metadata["plan"])
        snapshot_credits = @fulfillment.metadata["credits_per_period"]
        if @fulfillment.metadata.key?("credits_per_period")
          strict_positive_integer(snapshot_credits, "credits_per_period")
        elsif @plan
          @plan.credits_per_period
        else
          raise UsageCredits::InvalidOperation, "No subscription plan found for processor ID #{@fulfillment.metadata["plan"]} and no persisted credit snapshot"
        end
      when "credit_pack"
        pack_name = @fulfillment.metadata["pack"] || @fulfillment.metadata["pack_name"]
        pack = UsageCredits.find_credit_pack(pack_name)
        raise UsageCredits::InvalidOperation, "No credit pack named #{pack_name}" unless pack
        pack.total_credits
      else
        strict_positive_integer(@fulfillment.metadata["credits"], "credits")
      end
    end

    def calculate_expiration
      return nil unless @fulfillment.fulfillment_type == "subscription"

      rollover = if @fulfillment.metadata.key?("rollover_enabled")
        ActiveModel::Type::Boolean.new.cast(@fulfillment.metadata["rollover_enabled"])
      else
        @plan&.rollover_enabled
      end
      return nil if rollover

      # Cap the grace period to the fulfillment period to prevent balance accumulation
      # when fulfillment_period << grace_period (e.g., 15 seconds vs 5 minutes)
      fulfillment_period = UsageCredits::PeriodParser.parse_persisted_period(@fulfillment.fulfillment_period)
      effective_grace = [
        UsageCredits.configuration.fulfillment_grace_period,
        fulfillment_period
      ].min

      @fulfillment.calculate_next_fulfillment + effective_grace
    end

    def strict_positive_integer(value, name)
      number = Wallets::WholeNumber.parse(value, name: name, allow_string: true)
      raise UsageCredits::Error, "#{name} must be positive" unless number.positive?
      number
    rescue ArgumentError
      raise UsageCredits::Error, "#{name} must be a positive whole number"
    end

    def fulfillment_category
      case @fulfillment.fulfillment_type
      when "subscription" then "subscription_credits"
      when "credit_pack" then "credit_pack_purchase"
      else "credit_added"
      end
    end

    def fulfillment_metadata
      # Use string keys consistently to avoid duplicates after JSON serialization
      base_metadata = {
        "last_fulfilled_at" => Time.current,
        "reason" => "fulfillment_cycle",
        "fulfillment_period" => @fulfillment.fulfillment_period,
        "fulfillment_id" => @fulfillment.id
      }

      if @fulfillment.source.is_a?(Pay::Subscription)
        base_metadata["subscription_id"] = @fulfillment.source.id
      end

      @fulfillment.metadata.merge(base_metadata)
    end
  end
end
