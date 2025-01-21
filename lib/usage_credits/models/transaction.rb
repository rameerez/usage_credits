# frozen_string_literal: true

module UsageCredits
  # Tracks credit transactions in a wallet
  class Transaction < ApplicationRecord
    self.table_name = "usage_credits_transactions"

    belongs_to :wallet
    belongs_to :source, polymorphic: true, optional: true

    validates :amount, presence: true, numericality: { only_integer: true }
    validates :category, presence: true

    # Define transaction categories
    CATEGORIES = %w[
      signup_bonus
      referral_bonus
      subscription_credits
      subscription_monthly
      subscription_trial
      subscription_trial_expired
      subscription_signup_bonus
      subscription_monthly_reset
      trial_credits
      credit_pack
      credit_pack_purchase
      credit_pack_refund
      operation_charge
      credit_expiration
      manual_adjustment
      credit_added
      credit_deducted
    ].freeze

    validates :category, inclusion: { in: CATEGORIES }

    scope :credits_added, -> { where("amount > 0") }
    scope :credits_deducted, -> { where("amount < 0") }
    scope :by_category, ->(category) { where(category: category) }
    scope :recent, -> { order(created_at: :desc) }
    scope :expired, -> { where("expires_at < ?", Time.current) }
    scope :not_expired, -> {
      # A transaction is not expired if:
      # 1. It has no expiration date
      # 2. Its expiration date is in the future
      # 3. AND there are no expiration records for it (including same-second expirations)
      where(<<-SQL, Time.current, Time.current)
        (expires_at IS NULL OR expires_at > ?) AND
        NOT EXISTS (
          SELECT 1 FROM usage_credits_transactions exp
          WHERE exp.wallet_id = usage_credits_transactions.wallet_id
            AND exp.category = 'credit_expiration'
            AND exp.expires_at <= ?
            AND exp.created_at > usage_credits_transactions.created_at
        )
      SQL
    }
    scope :operation_charges, -> { where(category: :operation_charge) }

    # Format the amount for display
    def formatted_amount
      prefix = amount.positive? ? "+" : ""
      "#{prefix}#{UsageCredits.configuration.credit_formatter.call(amount)}"
    end

    # Check if the transaction has expired
    def expired?
      expires_at? && expires_at < Time.current
    end

    # Get the owner of the wallet
    def owner
      wallet.owner
    end

    # Get a human-readable description of the transaction
    def description
      return self[:description] if self[:description].present?

      case category
      when "credit_added"
        "Credits added"
      when "credit_deducted"
        "Credits deducted"
      when "subscription_monthly"
        "Monthly subscription credits"
      when "subscription_trial"
        "Trial credits"
      when "subscription_signup_bonus"
        "Signup bonus credits"
      when "subscription_monthly_reset"
        "Monthly credits reset"
      when "credit_pack_purchase"
        "Credit pack purchase"
      when "credit_expiration"
        "Credits expired"
      when "operation_charge"
        operation_description
      when "manual_adjustment"
        "Manual adjustment"
      else
        category.titleize
      end
    end

    # Override metadata getter to support both string and symbol keys
    def metadata
      @indifferent_metadata ||= ActiveSupport::HashWithIndifferentAccess.new(super || {})
    end

    # Override metadata setter to ensure consistent storage
    def metadata=(hash)
      @indifferent_metadata = nil  # Clear cache
      super(hash.is_a?(Hash) ? hash.to_h : {})
    end

    private

    def operation_description
      return "Operation charge" unless metadata["operation"]

      operation = metadata["operation"].to_s.titleize
      cost = metadata["cost"]
      "#{operation} (-#{cost} credits)"
    end
  end
end
