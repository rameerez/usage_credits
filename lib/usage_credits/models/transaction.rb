# frozen_string_literal: true

module UsageCredits
  # Tracks credit transactions in a wallet
  class Transaction < ApplicationRecord
    self.table_name = "usage_credits_transactions"

    belongs_to :wallet
    belongs_to :source, polymorphic: true, optional: true

    validates :amount, presence: true
    validates :category, presence: true

    # Define transaction categories
    CATEGORIES = %w[
      signup_bonus
      referral_bonus
      subscription_credits
      trial_credits
      credit_pack
      operation_charge
      credit_expiration
      manual_adjustment
    ].freeze

    validates :category, inclusion: { in: CATEGORIES }

    scope :credits_added, -> { where("amount > 0") }
    scope :credits_deducted, -> { where("amount < 0") }
    scope :by_category, ->(category) { where(category: category) }
    scope :recent, -> { order(created_at: :desc) }
    scope :expired, -> { where("expires_at < ?", Time.current) }
    scope :not_expired, -> { where("expires_at IS NULL OR expires_at > ?", Time.current) }

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

    private

    def operation_description
      return "Operation charge" unless metadata["operation"]

      operation = metadata["operation"].to_s.titleize
      cost = metadata["cost"]
      "#{operation} (-#{cost} credits)"
    end
  end
end
