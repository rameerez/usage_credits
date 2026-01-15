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
      "referral_bonus",                 # Referral reward bonus
      "bonus",                          # Generic bonus

      # Subscription-related
      "subscription_credits",           # Generic subscription credits
      "subscription_trial",             # Trial period credits
      "subscription_signup_bonus",      # Bonus for subscribing
      "subscription_upgrade",           # Plan upgrade credits

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

    has_many :outgoing_allocations,
              class_name: "UsageCredits::Allocation",
              foreign_key: :transaction_id,
              dependent: :destroy

    has_many :incoming_allocations,
              class_name: "UsageCredits::Allocation",
              foreign_key: :source_transaction_id,
              dependent: :destroy

    validates :amount, presence: true, numericality: { only_integer: true }
    validates :category, presence: true, inclusion: { in: CATEGORIES }

    validate :remaining_amount_cannot_be_negative

    # =========================================
    # Scopes
    # =========================================

    scope :credits_added, -> { where("amount > 0") }
    scope :credits_deducted, -> { where("amount < 0") }
    scope :by_category, ->(category) { where(category: category) }
    scope :recent, -> { order(created_at: :desc) }
    scope :operation_charges, -> { where(category: :operation_charge) }

    # A transaction is not expired if:
    # 1. It has no expiration date, OR
    # 2. Its expiration date is in the future
    scope :not_expired, -> { where("expires_at IS NULL OR expires_at > ?", Time.current) }
    scope :expired, -> { where("expires_at < ?", Time.current) }


    # =========================================
    # Helpers
    # =========================================

    # Get the owner of the wallet these credits belong to
    def owner
      wallet.owner
    end

    # Have these credits expired?
    def expired?
      expires_at.present? && expires_at < Time.current
    end

    # Is this transaction a positive credit or a negative (spend)?
    def credit?
      amount > 0
    end

    def debit?
      amount < 0
    end

    # How many credits from this transaction have already been allocated (spent)?
    # Only applies if this transaction is positive.
    def allocated_amount
      incoming_allocations.sum(:amount)
    end

    # How many credits remain unused in this positive transaction?
    # If negative, this will effectively be 0.
    def remaining_amount
      return 0 unless credit?
      amount - allocated_amount
    end

    # =========================================
    # Balance After Transaction
    # =========================================

    # Get the balance after this transaction was applied
    # Returns nil for transactions created before this feature was added
    def balance_after
      metadata[:balance_after]
    end

    # Get the balance before this transaction was applied
    # Returns the stored value if available, otherwise nil
    # Note: For transactions created before this feature, returns nil
    def balance_before
      metadata[:balance_before]
    end

    # =========================================
    # Display Formatting
    # =========================================

    # Format the amount for display (e.g., "+100 credits" or "-10 credits")
    def formatted_amount
      prefix = amount.positive? ? "+" : ""
      "#{prefix}#{UsageCredits.configuration.credit_formatter.call(amount)}"
    end

    # Format the balance after for display (e.g., "500 credits")
    # Returns nil if balance_after is not stored
    def formatted_balance_after
      return nil unless balance_after
      UsageCredits.configuration.credit_formatter.call(balance_after)
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
    # Metadata Handling
    # =========================================

    # Sync in-place modifications to metadata before saving
    before_save :sync_metadata_cache

    # Get metadata with indifferent access (string/symbol keys)
    # Returns empty hash if nil (for MySQL compatibility where JSON columns can't have defaults)
    def metadata
      @indifferent_metadata ||= ActiveSupport::HashWithIndifferentAccess.new(super || {})
    end

    # Set metadata, ensuring consistent storage format
    def metadata=(hash)
      @indifferent_metadata = nil  # Clear cache
      super(hash.is_a?(Hash) ? hash.to_h : {})
    end

    # Clear metadata cache on reload to ensure fresh data from database
    def reload(*)
      @indifferent_metadata = nil
      super
    end

    private

    # Sync in-place modifications to the cached metadata back to the attribute
    # This ensures changes like `metadata["key"] = "value"` are persisted on save
    def sync_metadata_cache
      write_attribute(:metadata, @indifferent_metadata.to_h) if @indifferent_metadata
    end

    # Format operation charge descriptions (e.g., "Process Video (-10 credits)")
    def operation_description
      operation = metadata["operation"]&.to_s&.titleize
      cost = metadata["cost"]

      return "Operation charge" if operation.blank?
      return operation if cost.blank?

      "#{operation} (-#{cost} credits)"
    end

    def remaining_amount_cannot_be_negative
      if credit? && remaining_amount < 0
        errors.add(:base, "Allocated amount exceeds transaction amount")
      end
    end

  end
end
