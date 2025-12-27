# frozen_string_literal: true

module UsageCredits
  # Extends Pay::Charge with credit pack functionality
  #
  # This extension integrates with the Pay gem (https://github.com/pay-rails/pay)
  # to automatically fulfill credit packs when charges succeed and handle refunds
  # when charges are refunded.
  module PayChargeExtension
    extend ActiveSupport::Concern

    included do
      after_initialize :init_metadata
      after_commit :fulfill_credit_pack!
      after_commit :handle_refund!, on: :update, if: :refund_needed?
    end

    def init_metadata
      self.metadata ||= {}
      self.data ||= {}
    end

    def succeeded?
      case type
      when "Pay::Stripe::Charge"
        status = data["status"] || data[:status]
        # Explicitly check for failure states
        return false if status == "failed"
        return false if status == "pending"
        return false if status == "canceled"
        return true if status == "succeeded"
        # Fallback: check if amount was actually captured
        return data["amount_captured"].to_i == amount.to_i && amount.to_i.positive?
      end

      # For non-Stripe charges, we assume Pay only creates charges after successful payment
      # This is a reasonable assumption based on Pay gem's behavior
      # TODO: Implement for more payment processors if needed
      true
    end

    def refunded?
      return false unless amount_refunded
      amount_refunded > 0
    end

    private

    # Returns true if the charge has a valid credit wallet to operate on
    # NOTE: We use original_credit_wallet to avoid auto-creating a wallet via ensure_credit_wallet
    def has_valid_wallet?
      return false unless customer&.owner&.respond_to?(:credit_wallet)
      # Check for existing wallet without triggering auto-creation
      if customer.owner.respond_to?(:original_credit_wallet)
        return customer.owner.original_credit_wallet.present?
      end
      customer.owner.credit_wallet.present?
    end

    def credit_wallet
      return nil unless has_valid_wallet?
      customer.owner.credit_wallet
    end

    def refund_needed?
      saved_change_to_amount_refunded? && amount_refunded.to_i.positive?
    end

    def is_credit_pack_purchase?
      metadata["purchase_type"] == "credit_pack"
    end

    def pack_identifier
      metadata["pack_name"]
    end

    def credits_already_fulfilled?
      # First check if there's a fulfillment record for this charge
      return true if UsageCredits::Fulfillment.exists?(source: self)

      # Fallback: check transactions directly:

      # Look up all transactions in the credit wallet for a purchase.
      transactions = credit_wallet&.transactions&.where(category: "credit_pack_purchase")
      return false unless transactions.present?

      begin
        adapter = ActiveRecord::Base.connection.adapter_name.downcase
        if adapter.include?("postgres")
          # PostgreSQL supports the @> JSON containment operator.
          transactions.exists?(['metadata @> ?', { purchase_charge_id: id, credits_fulfilled: true }.to_json])
        else
          # For other adapters (e.g. SQLite, MySQL), try using JSON_EXTRACT.
          transactions.exists?(["json_extract(metadata, '$.purchase_charge_id') = ? AND json_extract(metadata, '$.credits_fulfilled') = ?", id, true])
        end
      rescue ActiveRecord::StatementInvalid
        # If the SQL query fails (for example, if JSON_EXTRACT isn’t supported),
        # fall back to loading transactions in Ruby and filtering them.
        transactions.any? do |tx|
          data =
            if tx.metadata.is_a?(Hash)
              tx.metadata
            else
              JSON.parse(tx.metadata) rescue {}
            end
          data["purchase_charge_id"].to_i == id.to_i && data["credits_fulfilled"].to_s == "true"
        end
      end
    end

    def fulfill_credit_pack!
      return unless is_credit_pack_purchase?
      return unless pack_identifier
      return unless has_valid_wallet?
      return unless succeeded?
      return if refunded?
      return if credits_already_fulfilled?

      Rails.logger.info "Starting to process charge #{id} to fulfill credits"

      pack_name = pack_identifier.to_sym
      pack = UsageCredits.find_pack(pack_name)

      unless pack
        Rails.logger.error "Credit pack not found: #{pack_name} for charge #{id}"
        return
      end

      # Validate that the pack details match if they're provided in metadata
      if metadata["credits"].present?
        expected_credits = metadata["credits"].to_i
        if expected_credits != pack.credits
          Rails.logger.error "Credit pack mismatch: expected #{expected_credits} credits but pack #{pack_name} provides #{pack.credits}"
          return
        end
      end

      begin
        # Add credits to the user's wallet
        credit_wallet.add_credits(
          pack.total_credits,
          category: "credit_pack_purchase",
          metadata: {
            purchase_charge_id: id,
            purchased_at: created_at,
            credits_fulfilled: true,
            fulfilled_at: Time.current,
            **pack.base_metadata
          }
        )

        # Also create a one-time fulfillment record for audit and consistency
        # This Fulfillment record won't get picked up by the fulfillment job because `next_fulfillment_at` is nil
        Fulfillment.create!(
          wallet: credit_wallet,
          source: self, # the Pay::Charge
          fulfillment_type: "credit_pack",
          credits_last_fulfillment: pack.total_credits,
          last_fulfilled_at: Time.current,
          next_fulfillment_at: nil, # so it doesn't get re-processed
          metadata: {
            purchase_charge_id: id,
            purchased_at: created_at,
            **pack.base_metadata
          }
        )

        Rails.logger.info "Successfully fulfilled credit pack #{pack_name} for charge #{id}"
      rescue StandardError => e
        Rails.logger.error "Failed to fulfill credit pack #{pack_name} for charge #{id}: #{e.message}"
        raise
      end
    end

    # Returns the total credits already refunded for this charge
    def credits_previously_refunded
      transactions = credit_wallet&.transactions&.where(category: "credit_pack_refund")
      return 0 unless transactions.present?

      # Sum all refund transactions for this charge (amounts are negative, so we negate)
      transactions.select do |tx|
        data = tx.metadata.is_a?(Hash) ? tx.metadata : (JSON.parse(tx.metadata) rescue {})
        data["refunded_purchase_charge_id"].to_i == id.to_i && data["credits_refunded"].to_s == "true"
      end.sum { |tx| -tx.amount }
    end

    def credits_already_refunded?
      # Check if any refund was already processed for this charge
      credits_previously_refunded > 0
    end

    def fully_refunded?
      # Check if a full refund (100%) has already been processed
      pack = UsageCredits.find_pack(pack_identifier&.to_sym)
      return false unless pack
      credits_previously_refunded >= pack.total_credits
    end

    def handle_refund!
      # Guard clauses for required data and state
      return unless refunded?
      return unless pack_identifier
      return unless has_valid_wallet?
      return unless amount.is_a?(Numeric) && amount.positive?

      pack_name = pack_identifier.to_sym
      pack = UsageCredits.find_pack(pack_name)

      unless pack
        Rails.logger.error "Credit pack not found for refund: #{pack_name} for charge #{id}"
        return
      end

      # Validate refund amount
      if amount_refunded > amount
        Rails.logger.error "Invalid refund amount: #{amount_refunded} exceeds original charge amount #{amount} for charge #{id}"
        return
      end

      # Calculate total credits that SHOULD be refunded based on current refund amount
      refund_ratio = amount_refunded.to_f / amount.to_f
      total_credits_to_refund = (pack.total_credits * refund_ratio).ceil

      # Calculate credits already refunded (for incremental/partial refunds)
      already_refunded = credits_previously_refunded

      # Only deduct the INCREMENTAL amount (difference between what should be refunded and what's already refunded)
      credits_to_remove = total_credits_to_refund - already_refunded

      # Skip if nothing new to refund
      if credits_to_remove <= 0
        Rails.logger.info "Refund for charge #{id} already processed (#{already_refunded} credits already refunded)"
        return
      end

      begin
        Rails.logger.info "Processing refund for charge #{id}: #{credits_to_remove} credits (incremental from #{already_refunded} to #{total_credits_to_refund})"

        credit_wallet.deduct_credits(
          credits_to_remove,
          category: "credit_pack_refund",
          metadata: {
            refunded_purchase_charge_id: id,
            credits_refunded: true,
            refunded_at: Time.current,
            refund_percentage: refund_ratio,
            refund_amount_cents: amount_refunded,
            incremental_credits: credits_to_remove,
            total_credits_refunded: total_credits_to_refund,
            **pack.base_metadata
          }
        )

        Rails.logger.info "Successfully processed refund for charge #{id}"
      rescue UsageCredits::InsufficientCredits => e
        Rails.logger.error "Insufficient credits for refund on charge #{id}: #{e.message}"
        # If negative balance not allowed and user has used credits,
        # we'll let the error propagate
        raise
      rescue StandardError => e
        Rails.logger.error "Failed to process refund for charge #{id}: #{e.message}"
        raise
      end
    end

  end
end
