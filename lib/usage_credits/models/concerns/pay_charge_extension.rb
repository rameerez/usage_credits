# frozen_string_literal: true

module UsageCredits
  # Extends Pay::Charge with credit pack functionality
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
      return true if data["status"] == "succeeded" || data[:status] == "succeeded"
      # For Stripe charges, a successful charge has amount_captured equal to the charge amount
      return true if type == "Pay::Stripe::Charge" && data["amount_captured"] == amount
      false
    end

    def refunded?
      return false unless amount_refunded
      amount_refunded > 0
    end

    private

    # Returns true if the charge has a valid credit wallet to operate on
    def has_valid_wallet?
      return false unless customer&.owner&.respond_to?(:credit_wallet)
      return false unless customer.owner.credit_wallet.present?
      true
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

      # Fallback: check transactions directly
      credit_wallet&.transactions&.where(category: "credit_pack_purchase")
        .exists?(['metadata @> ?', { purchase_charge_id: id, credits_fulfilled: true }.to_json])
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
        # Wrap credit addition in a transaction for atomicity
        ActiveRecord::Base.transaction do
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
        end

        Rails.logger.info "Successfully fulfilled credit pack #{pack_name} for charge #{id}"
      rescue StandardError => e
        Rails.logger.error "Failed to fulfill credit pack #{pack_name} for charge #{id}: #{e.message}"
        raise
      end
    end

    def credits_already_refunded?
      # Check if refund was already processed with credits deducted by looking for a refund transaction
      credit_wallet&.transactions&.where(category: "credit_pack_refund")
        .exists?(['metadata @> ?', { refunded_purchase_charge_id: id, credits_refunded: true }.to_json])
    end

    def handle_refund!
      # Guard clauses for required data and state
      return unless refunded?
      return unless pack_identifier
      return unless has_valid_wallet?
      return unless amount.is_a?(Numeric) && amount.positive?
      return if credits_already_refunded?

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

      # Calculate refund ratio and credits to remove
      # Always use ceil for credit calculations to avoid giving more credits than paid for
      refund_ratio = amount_refunded.to_f / amount.to_f
      credits_to_remove = (pack.total_credits * refund_ratio).ceil

      begin
        Rails.logger.info "Processing refund for charge #{id}: #{credits_to_remove} credits (#{(refund_ratio * 100).round(2)}% of #{pack.total_credits})"

        # Wrap credit deduction in a transaction for atomicity
        ActiveRecord::Base.transaction do
          credit_wallet.deduct_credits(
            credits_to_remove,
            category: "credit_pack_refund",
            metadata: {
              refunded_purchase_charge_id: id,
              credits_refunded: true,
              refunded_at: Time.current,
              refund_percentage: refund_ratio,
              refund_amount_cents: amount_refunded,
              **pack.base_metadata
            }
          )
        end

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
