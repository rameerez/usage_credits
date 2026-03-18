# frozen_string_literal: true

module UsageCredits
  # Records all credit changes in a wallet (additions, deductions, expirations).
  #
  # This class extends Wallets::Transaction with usage_credits-specific features:
  #   - Fulfillment tracking for subscription/pack credits
  #   - Usage-credits specific transaction categories
  #   - Operation charge descriptions and formatting

  class Transaction < Wallets::Transaction
    # =========================================
    # Embeddability Configuration
    # =========================================

    self.embedded_table_name = "usage_credits_transactions"
    self.config_provider = -> { UsageCredits.configuration }

    # =========================================
    # Transaction Categories
    # =========================================

    # Override base categories with usage_credits-specific ones
    DEFAULT_CATEGORIES = [
      # Bonus credits
      "signup_bonus",
      "referral_bonus",
      "bonus",

      # Subscription-related
      "subscription_credits",
      "subscription_trial",
      "subscription_signup_bonus",
      "subscription_upgrade",

      # One-time purchases
      "credit_pack",
      "credit_pack_purchase",
      "credit_pack_refund",

      # Credit usage & management
      "operation_charge",
      "manual_adjustment",
      "credit_added",
      "credit_deducted",

      # Transfer categories (from wallets)
      "transfer_in",
      "transfer_out"
    ].freeze

    CATEGORIES = DEFAULT_CATEGORIES

    def self.categories
      (DEFAULT_CATEGORIES + resolved_config.additional_categories).uniq
    end

    # =========================================
    # Additional Associations
    # =========================================

    belongs_to :wallet, class_name: "UsageCredits::Wallet"
    belongs_to :transfer, class_name: "UsageCredits::Transfer", optional: true
    belongs_to :fulfillment, class_name: "UsageCredits::Fulfillment", optional: true

    # Re-declare allocation associations with correct classes
    has_many :outgoing_allocations,
             class_name: "UsageCredits::Allocation",
             foreign_key: :transaction_id,
             dependent: :destroy

    has_many :incoming_allocations,
             class_name: "UsageCredits::Allocation",
             foreign_key: :source_transaction_id,
             dependent: :destroy

    # =========================================
    # Backwards Compatibility Scopes
    # =========================================

    scope :credits_added, -> { where("amount > 0") }
    scope :credits_deducted, -> { where("amount < 0") }
    scope :operation_charges, -> { where(category: :operation_charge) }

    # =========================================
    # Display Formatting
    # =========================================

    # Format the amount for display (e.g., "+100 credits" or "-10 credits")
    def formatted_amount
      prefix = amount.positive? ? "+" : ""
      "#{prefix}#{UsageCredits.configuration.credit_formatter.call(amount)}"
    end

    # Format the balance after for display (e.g., "500 credits")
    def formatted_balance_after
      return nil unless balance_after
      UsageCredits.configuration.credit_formatter.call(balance_after)
    end

    # Get a human-readable description of what this transaction represents
    def description
      return self[:description] if self[:description].present?
      return operation_description if category == "operation_charge"
      category.titleize
    end

    private

    # Format operation charge descriptions (e.g., "Process Video (-10 credits)")
    def operation_description
      operation = metadata["operation"]&.to_s&.titleize
      cost = metadata["cost"]

      return "Operation charge" if operation.blank?
      return operation if cost.blank?

      "#{operation} (-#{cost} credits)"
    end
  end
end
