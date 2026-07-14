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
      after_commit :fulfill_credit_pack!, on: [:create, :update]
      after_commit :handle_refund!, on: :update, if: :refund_needed?
    end

    def init_metadata
      self.metadata ||= {}
      self.data ||= {}
    end

    def succeeded?
      case type
      when "Pay::Stripe::Charge"
        # Pay 10+ stores the full Stripe charge object in `object` column
        # Older Pay versions stored charge details in `data` column
        # We check both for backward compatibility
        stripe_object = charge_object_data
        status = stripe_object["status"]

        # Explicitly check for failure states
        return false if status == "failed"
        return false if status == "pending"
        return false if status == "canceled"
        return true if status == "succeeded"

        # Fallback: check if amount was actually captured
        amount_captured = stripe_object["amount_captured"].to_i
        return amount_captured == amount.to_i && amount.to_i.positive?
      end

      # Pay's non-Stripe adapters persist Pay::Charge rows only after their
      # processor-specific success event (for example, Paddle Billing ignores
      # every transaction whose status is not "completed").
      true
    end

    # Returns the Stripe charge object data, checking both `object` (Pay 10+)
    # and `data` (older Pay versions) for backward compatibility
    def charge_object_data
      # Pay 10+ stores full Stripe object in `object` column
      if respond_to?(:object) && object.is_a?(Hash) && object.any?
        object.with_indifferent_access
      # Older Pay versions stored charge details in `data` column
      elsif data.is_a?(Hash) && data.any?
        data.with_indifferent_access
      else
        {}.with_indifferent_access
      end
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

    # Checkout metadata is the immutable commercial snapshot: it records what
    # the customer bought at payment time. Runtime configuration may be edited
    # or the pack may be removed before a delayed webhook/refund arrives, so it
    # must only be a legacy fallback, never the source of truth for quantities.
    def credit_pack_snapshot
      pack_name = pack_identifier.to_s
      pack = UsageCredits.find_pack(pack_name.to_sym)

      credits = strict_metadata_integer("credits", fallback: pack&.credits)
      bonus_credits = strict_metadata_integer("bonus_credits", fallback: pack&.bonus_credits || 0)
      return if credits.nil? || bonus_credits.nil? || !credits.positive? || bonus_credits.negative?

      snapshot = {
        pack_name: pack_name,
        credits: credits,
        bonus_credits: bonus_credits,
        total_credits: credits + bonus_credits,
        price_cents: strict_metadata_integer("price_cents", fallback: pack&.price_cents),
        price_currency: (metadata["price_currency"].presence || pack&.price_currency || currency).to_s.upcase
      }

      if pack && (pack.credits != credits || pack.bonus_credits != bonus_credits)
        Rails.logger.warn "Credit pack #{pack_name} changed after charge #{id}; honoring checkout snapshot (#{credits} + #{bonus_credits} credits)"
      end

      snapshot
    rescue ArgumentError => e
      Rails.logger.error "Invalid credit pack metadata for charge #{id}: #{e.message}"
      nil
    end

    def strict_metadata_integer(key, fallback: nil)
      value = metadata[key]
      value = fallback if value.nil? || (value.respond_to?(:empty?) && value.empty?)
      return nil if value.nil?

      Wallets::WholeNumber.parse(value, name: key, allow_string: true)
    end

    def credits_already_fulfilled?
      # First check if there's a fulfillment record for this charge
      return true if UsageCredits::Fulfillment.exists?(source: self)

      # Fallback: check transactions directly:

      # Look up all transactions in the credit wallet for a purchase.
      transactions = credit_wallet&.transactions&.where(category: "credit_pack_purchase")
      return false unless transactions.present?

      begin
        adapter = transactions.connection.adapter_name.downcase
        if adapter.include?("postgres")
          # PostgreSQL supports the @> JSON containment operator.
          transactions.exists?(["metadata @> ?", {purchase_charge_id: id, credits_fulfilled: true}.to_json])
        elsif adapter.include?("mysql")
          # MySQL: JSON_EXTRACT returns JSON values, use CAST for proper comparison
          transactions.exists?([
            "JSON_EXTRACT(metadata, '$.purchase_charge_id') = CAST(? AS JSON) AND JSON_EXTRACT(metadata, '$.credits_fulfilled') = CAST('true' AS JSON)",
            id
          ])
        else
          # SQLite: json_extract returns SQL values (true becomes 1)
          transactions.exists?(["json_extract(metadata, '$.purchase_charge_id') = ? AND json_extract(metadata, '$.credits_fulfilled') = ?", id, 1])
        end
      rescue ActiveRecord::StatementInvalid
        # If the SQL query fails (for example, if JSON_EXTRACT isn’t supported),
        # fall back to loading transactions in Ruby and filtering them.
        transactions.any? do |tx|
          data =
            if tx.metadata.is_a?(Hash)
              tx.metadata
            else
              begin
                JSON.parse(tx.metadata)
              rescue
                {}
              end
            end
          data["purchase_charge_id"].to_i == id.to_i && data["credits_fulfilled"].to_s == "true"
        end
      end
    end

    def fulfill_credit_pack!
      return unless is_credit_pack_purchase?
      return unless pack_identifier.present?
      return unless has_valid_wallet?
      return unless succeeded?
      return if refunded?
      return if credits_already_fulfilled?

      Rails.logger.info "Starting to process charge #{id} to fulfill credits"

      snapshot = credit_pack_snapshot
      unless snapshot
        Rails.logger.error "Credit pack snapshot is missing or invalid for charge #{id}"
        return
      end

      begin
        wallet = credit_wallet
        credit_transaction = nil
        fulfillment = nil
        fulfilled = false

        # The wallet lock serializes duplicate webhook deliveries for the same
        # owner. Re-check idempotency inside that lock; the database's unique
        # source index is the final guard against duplicate fulfillment rows.
        wallet.with_lock do
          next if UsageCredits::Fulfillment.exists?(source: self)

          fulfilled_at = Time.current
          fulfillment = Fulfillment.create!(
            wallet: wallet,
            source: self,
            fulfillment_type: "credit_pack",
            credits_last_fulfillment: snapshot.fetch(:total_credits),
            last_fulfilled_at: fulfilled_at,
            next_fulfillment_at: nil,
            metadata: snapshot.merge(
              purchase_charge_id: id,
              purchased_at: created_at
            )
          )

          credit_transaction = wallet.add_credits(
            snapshot.fetch(:total_credits),
            category: "credit_pack_purchase",
            fulfillment: fulfillment,
            metadata: {
              purchase_charge_id: id,
              purchased_at: created_at,
              credits_fulfilled: true,
              fulfilled_at: fulfilled_at,
              **snapshot
            }
          )
          fulfilled = true
        end

        return unless fulfilled

        # Dispatch credit_pack_purchased callback after successful fulfillment
        # Note: credits_added callback was already fired by add_credits
        ActiveRecord.after_all_transactions_commit do
          UsageCredits::Callbacks.dispatch(:credit_pack_purchased,
            wallet: wallet,
            amount: snapshot.fetch(:total_credits),
            transaction: credit_transaction,
            metadata: {
              credit_pack_name: snapshot.fetch(:pack_name).to_sym,
              credit_pack: UsageCredits.find_pack(snapshot.fetch(:pack_name).to_sym),
              pay_charge: self,
              fulfillment: fulfillment,
              price_cents: snapshot[:price_cents]
            })
        end

        Rails.logger.info "Successfully fulfilled credit pack #{snapshot.fetch(:pack_name)} for charge #{id}"
      rescue ActiveRecord::RecordNotUnique
        # A concurrent delivery committed the unique source row first. Treat
        # that committed fulfillment as the idempotent winner.
        return if UsageCredits::Fulfillment.exists?(source: self)
        raise
      rescue => e
        Rails.logger.error "Failed to fulfill credit pack #{pack_identifier} for charge #{id}: #{e.message}"
        raise
      end
    end

    # Returns the total credits already refunded for this charge
    # Note: NOT memoized because refunds can happen incrementally within the same request
    def credits_previously_refunded
      transactions = credit_wallet&.transactions&.where(category: "credit_pack_refund")
      return 0 unless transactions.present?

      # Try database-level filtering first (more efficient)
      begin
        adapter = transactions.connection.adapter_name.downcase
        filtered =
          if adapter.include?("postgres")
            # PostgreSQL supports the @> JSON containment operator
            transactions.where(
              "metadata @> ?",
              {refunded_purchase_charge_id: id, credits_refunded: true}.to_json
            )
          elsif adapter.include?("mysql")
            # MySQL: JSON_EXTRACT returns JSON values, use CAST for proper comparison
            transactions.where(
              "JSON_EXTRACT(metadata, '$.refunded_purchase_charge_id') = CAST(? AS JSON) AND JSON_EXTRACT(metadata, '$.credits_refunded') = CAST('true' AS JSON)",
              id
            )
          else
            # SQLite: json_extract returns SQL values (true becomes 1)
            transactions.where(
              "json_extract(metadata, '$.refunded_purchase_charge_id') = ? AND json_extract(metadata, '$.credits_refunded') = ?",
              id, 1
            )
          end

        return filtered.sum { |tx| -tx.amount }
      rescue ActiveRecord::StatementInvalid => e
        Rails.logger.warn "JSON query failed, falling back to Ruby filtering: #{e.message}"
      end

      # Fallback: filter in Ruby (for databases without JSON support)
      # Sum in a single pass to avoid multiple iterations
      transactions.sum do |tx|
        data = tx.metadata.is_a?(Hash) ? tx.metadata : begin
          JSON.parse(tx.metadata)
        rescue
          {}
        end
        if data["refunded_purchase_charge_id"].to_i == id.to_i && data["credits_refunded"].to_s == "true"
          -tx.amount
        else
          0
        end
      end
    end

    def handle_refund!
      # Guard clauses for required data and state
      return unless refunded?
      return unless pack_identifier.present?
      return unless has_valid_wallet?
      return unless amount.is_a?(Numeric) && amount.positive?

      fulfillment = UsageCredits::Fulfillment.find_by(source: self)
      # Processor metadata proves what a charge was intended to buy, not that
      # the corresponding credits were ever issued. A refund can arrive for a
      # charge whose fulfillment failed (or whose create webhook was never
      # delivered); clawing that metadata snapshot back would manufacture
      # credit debt for value the customer never received. Keep the legacy
      # transaction lookup for pre-1.0 purchases that predate Fulfillment rows.
      unless fulfillment || credits_already_fulfilled?
        Rails.logger.error "Cannot refund credits for charge #{id}: no completed credit fulfillment exists"
        return
      end

      snapshot = fulfillment&.metadata&.symbolize_keys || credit_pack_snapshot
      total_purchased_credits = fulfillment&.credits_last_fulfillment || snapshot&.fetch(:total_credits, nil)
      unless snapshot && total_purchased_credits&.positive?
        Rails.logger.error "Original credit pack fulfillment is missing for refund on charge #{id}"
        return
      end

      # Validate refund amount
      if amount_refunded > amount
        Rails.logger.error "Invalid refund amount: #{amount_refunded} exceeds original charge amount #{amount} for charge #{id}"
        return
      end

      begin
        wallet = credit_wallet
        refund_transaction = nil

        # Both the cumulative-refund query and the new debit live under the
        # wallet lock. Concurrent partial/full refund webhooks therefore apply
        # only the remaining delta, never the same clawback twice.
        wallet.with_lock do
          already_refunded = credits_previously_refunded
          total_credits_to_refund = divide_rounding_up(
            total_purchased_credits * amount_refunded.to_i,
            amount.to_i
          )
          credits_to_remove = total_credits_to_refund - already_refunded

          if credits_to_remove <= 0
            Rails.logger.info "Refund for charge #{id} already processed (#{already_refunded} credits already refunded)"
            next
          end

          refund_ratio = amount_refunded.to_f / amount.to_f
          Rails.logger.info "Processing refund for charge #{id}: #{credits_to_remove} credits (incremental from #{already_refunded} to #{total_credits_to_refund})"

          refund_transaction = wallet.send(
            :deduct_refunded_credits,
            credits_to_remove,
            fulfillment: fulfillment,
            metadata: snapshot.merge(
              refunded_purchase_charge_id: id,
              credits_refunded: true,
              refunded_at: Time.current,
              refund_percentage: refund_ratio,
              refund_amount_cents: amount_refunded,
              incremental_credits: credits_to_remove,
              total_credits_refunded: total_credits_to_refund
            )
          )
        end

        return unless refund_transaction

        Rails.logger.info "Successfully processed refund for charge #{id}"
      rescue => e
        Rails.logger.error "Failed to process refund for charge #{id}: #{e.message}"
        raise
      end
    end

    def divide_rounding_up(numerator, denominator)
      numerator.div(denominator) + (numerator.remainder(denominator).zero? ? 0 : 1)
    end
  end
end
