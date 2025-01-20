module UsageCredits
  module ChargeExtension
    extend ActiveSupport::Concern

    included do
      after_initialize do
        self.metadata ||= {}
        self.data ||= {}
      end

      after_commit :fulfill_credit_pack, on: :create, if: :should_fulfill_credit_pack?
      after_commit :handle_refund, on: :update, if: :refunded?
    end

    def succeeded?
      data&.dig("status") == "succeeded"
    end

    private

    def should_fulfill_credit_pack?
      # Only fulfill if:
      # 1. Payment succeeded
      # 2. This is a credit pack purchase
      # 3. Not a refund
      # 4. Not already fulfilled
      succeeded? &&
        metadata&.dig("credit_pack").present? &&
        !refunded? &&
        !metadata&.dig("credits_fulfilled")
    end

    def handle_refund
      return unless metadata&.dig("credit_pack").present?
      return unless metadata&.dig("credits_fulfilled")
      return if metadata&.dig("credits_refunded")

      pack = UsageCredits.configuration.credit_packs[metadata["credit_pack"].to_sym]
      return unless pack

      # Calculate refund percentage
      refund_percentage = amount_refunded.to_f / amount.to_f

      # Calculate credits to remove (proportional to refund amount)
      credits_to_remove = (pack.credits * refund_percentage).round

      if credits_to_remove > 0
        customer.owner.credit_wallet.deduct_credits(
          credits_to_remove,
          category: :credit_pack_refund,
          metadata: {
            pack_id: metadata["credit_pack"],
            charge_id: id,
            processor: customer.processor,
            currency: currency,
            amount_refunded: amount_refunded,
            refund_percentage: refund_percentage
          }
        )

        # Mark as refunded to prevent double processing
        update_column(:metadata, metadata.merge("credits_refunded" => true))
      end
    end

    def fulfill_credit_pack
      pack = UsageCredits.configuration.credit_packs[metadata["credit_pack"].to_sym]
      return unless pack

      customer.owner.credit_wallet.add_credits(
        pack.credits,
        category: :credit_pack_purchase,
        metadata: {
          pack: metadata["credit_pack"],
          charge_id: id,
          processor: customer.processor,
          currency: currency,
          amount: amount,
          price_cents: amount,
          credits: pack.credits,
          purchased_at: Time.current
        }
      )

      # Mark as fulfilled to prevent double processing
      update_column(:metadata, metadata.merge("credits_fulfilled" => true))
    end
  end
end
