# lib/usage_credits/services/fulfillment_service.rb
module UsageCredits
  class FulfillmentService
    def self.process_pending_fulfillments
      count = 0
      Fulfillment.due_for_fulfillment.find_each do |fulfillment|
        new(fulfillment).process
        count += 1
      end
      count
    end

    def initialize(fulfillment)
      @fulfillment = fulfillment
    end

    def process
      ActiveRecord::Base.transaction do
        @fulfillment.lock! # row lock to avoid double awarding

        # re-check if it's still due, in case time changed or another process already updated it
        break unless @fulfillment.due_for_fulfillment?

        credits = calculate_credits
        give_credits(credits)
        update_fulfillment(credits)
      end
    rescue => e
      Rails.logger.error "Failed to process fulfillment #{@fulfillment.id}: #{e.message}"
      raise
    end

    private

    def give_credits(credits)
      @fulfillment.wallet.add_credits(
        credits,
        category: fulfillment_category,
        fulfillment: @fulfillment,
        metadata: fulfillment_metadata
      )
    end

    def update_fulfillment(credits)
      @fulfillment.update!(
        fulfilled_at: Time.current,
        credits_last_fulfillment: credits,
        next_fulfillment_at: @fulfillment.calculate_next_fulfillment
      )
    end

    def calculate_credits
      case @fulfillment.fulfillment_type
      when "subscription"
        plan = UsageCredits.credit_subscription_plans[@fulfillment.metadata["plan"].to_sym]
        raise ArgumentError, "No subscription plan named #{@fulfillment.metadata["plan"}" unless plan
        plan.credits_per_period
      when "credit_pack"
        pack = UsageCredits.credit_packs[@fulfillment.metadata["pack"].to_sym]
        raise ArgumentError, "No credit pack named #{@fulfillment.metadata["pack"]}" unless pack
        pack.total_credits
      else
        @fulfillment.metadata["credits"].to_i
      end
    end

    def fulfillment_category
      case @fulfillment.fulfillment_type
      when "subscription" then "subscription_credits"
      when "credit_pack" then "credit_pack_purchase"
      else "credit_added"
      end
    end

    def fulfillment_metadata
      @fulfillment.metadata.merge(
        fulfilled_at: Time.current,
        fulfillment_id: @fulfillment.id
      )
    end
  end
end
