# frozen_string_literal: true

module UsageCredits
  # Records all credit changes in a wallet (additions, deductions, expirations).
  #
  # Each transaction represents a single credit operation and includes:
  #   - amount: How many credits (positive for additions, negative for deductions)
  #   - category: What kind of operation (subscription fulfillment, pack purchase, etc)
  #   - metadata: Additional details about the operation
  #   - expires_at: When these credits expire (optional)
  class Transaction < ApplicationRecord
    self.table_name = "usage_credits_transactions"

    # =========================================
    # Transaction Categories
    # =========================================

    # All possible transaction types, grouped by purpose:
    CATEGORIES = [
      # Bonus credits
      "signup_bonus",                   # Initial signup bonus
      "referral_bonus",                 # Referral reward

      # Subscription-related
      "subscription_credits",           # Generic subscription credits
      "subscription_trial",             # Trial period credits
      "subscription_signup_bonus",      # Bonus for subscribing

      # One-time purchases
      "credit_pack",                    # Generic credit pack
      "credit_pack_purchase",           # Credit pack bought
      "credit_pack_refund",             # Credit pack refunded

      # Credit usage & management
      "operation_charge",               # Credits spent on operation
      "manual_adjustment",              # Manual admin adjustment
      "credit_added",                   # Generic addition
      "credit_deducted"                 # Generic deduction
    ].freeze

    # =========================================
    # Associations & Validations
    # =========================================

    belongs_to :wallet

    belongs_to :fulfillment, optional: true

    validates :amount, presence: true, numericality: { only_integer: true }
    validates :category, presence: true, inclusion: { in: CATEGORIES }

    # =========================================
    # Scopes
    # =========================================

    scope :credits_added, -> { where("amount > 0") }
    scope :credits_deducted, -> { where("amount < 0") }
    scope :by_category, ->(category) { where(category: category) }
    scope :recent, -> { order(created_at: :desc) }
    scope :expired, -> { where("expires_at < ?", Time.current) }
    scope :operation_charges, -> { where(category: :operation_charge) }

    # A transaction is not expired if:
    # 1. It has no expiration date, OR
    # 2. Its expiration date is in the future
    scope :not_expired, -> { where("expires_at IS NULL OR expires_at > ?", Time.current) }
    scope :expired, -> { where("expires_at < ?", Time.current) }


    # =========================================
    # Display Formatting
    # =========================================

    # Format the amount for display (e.g., "+100 credits" or "-10 credits")
    def formatted_amount
      prefix = amount.positive? ? "+" : ""
      "#{prefix}#{UsageCredits.configuration.credit_formatter.call(amount)}"
    end

    # Get a human-readable description of what this transaction represents
    def description
      # Custom description takes precedence
      return self[:description] if self[:description].present?

      # Operation charges have dynamic descriptions
      return operation_description if category == "operation_charge"

      # Use predefined description or fallback to titleized category
      category.titleize
    end

    # =========================================
    # State & Relations
    # =========================================

    # Check if these credits have expired
    def expired?
      expires_at? && expires_at < Time.current
    end

    # Get the owner of the wallet these credits belong to
    def owner
      wallet.owner
    end

    # =========================================
    # Metadata Handling
    # =========================================

    # Get metadata with indifferent access (string/symbol keys)
    def metadata
      @indifferent_metadata ||= ActiveSupport::HashWithIndifferentAccess.new(super || {})
    end

    # Set metadata, ensuring consistent storage format
    def metadata=(hash)
      @indifferent_metadata = nil  # Clear cache
      super(hash.is_a?(Hash) ? hash.to_h : {})
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
