# lib/usage_credits/services/fulfillment_service.rb
module UsageCredits
  class FulfillmentService
    def self.process_pending_fulfillments
      count = 0
      failed = 0

      Fulfillment.due_for_fulfillment.find_each do |fulfillment|
        begin
          new(fulfillment).process
          count += 1
        rescue StandardError => e
          failed += 1
          Rails.logger.error "Failed to process fulfillment #{fulfillment.id}: #{e.message}"
          Rails.logger.error e.backtrace.join("\n")
          next # Continue with next fulfillment
        end
      end

      Rails.logger.info "Processed #{count} fulfillments (#{failed} failed)"
      count
    end

    def initialize(fulfillment)
      @fulfillment = fulfillment
      validate_fulfillment!
    end

    def process
      ActiveRecord::Base.transaction do
        @fulfillment.lock! # row lock to avoid double awarding

        # re-check if it's still due, in case time changed or another process already updated it
        return unless @fulfillment.due_for_fulfillment?

        credits = calculate_credits
        give_credits(credits)
        update_fulfillment(credits)
      end
    rescue UsageCredits::Error => e
      Rails.logger.error "Usage credits error processing fulfillment #{@fulfillment.id}: #{e.message}"
      raise
    rescue StandardError => e
      Rails.logger.error "Unexpected error processing fulfillment #{@fulfillment.id}: #{e.message}"
      raise
    end

    private

    def validate_fulfillment!
      raise UsageCredits::Error, "No fulfillment provided" if @fulfillment.nil?
      raise UsageCredits::Error, "Invalid fulfillment type" unless ["subscription", "credit_pack", "manual"].include?(@fulfillment.fulfillment_type)
      raise UsageCredits::Error, "No wallet associated with fulfillment" if @fulfillment.wallet.nil?

      # Validate required metadata based on type
      case @fulfillment.fulfillment_type
      when "subscription"
        raise UsageCredits::Error, "No plan specified in metadata" unless @fulfillment.metadata["plan"].present?
      when "credit_pack"
        raise UsageCredits::Error, "No pack specified in metadata" unless @fulfillment.metadata["pack"].present?
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
        raise UsageCredits::InvalidOperation, "No subscription plan found for processor ID #{@fulfillment.metadata["plan"]}" unless @plan
        @plan.credits_per_period
      when "credit_pack"
        pack = UsageCredits.find_credit_pack(@fulfillment.metadata["pack"])
        raise UsageCredits::InvalidOperation, "No credit pack named #{@fulfillment.metadata["pack"]}" unless pack
        pack.total_credits
      else
        @fulfillment.metadata["credits"].to_i
      end
    end

    def calculate_expiration
      return nil unless @fulfillment.fulfillment_type == "subscription" && @plan
      return nil if @plan.rollover_enabled

      @fulfillment.calculate_next_fulfillment + UsageCredits.configuration.fulfillment_grace_period
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
