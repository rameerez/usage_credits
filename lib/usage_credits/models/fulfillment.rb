# frozen_string_literal: true

module UsageCredits
  # A Fulfillment represents a credit-giving action triggered by a purchase,
  # including credit pack purchases and subscriptions.
  # Some of this credit-giving actions are repeating in nature (i.e.: subscriptions), some are not (one-time purchases)
  class Fulfillment < ApplicationRecord
    self.table_name = "usage_credits_fulfillments"

    belongs_to :wallet
    belongs_to :source, polymorphic: true, optional: true

    validates :wallet, presence: true
    validates :credits_last_fulfillment, presence: true, numericality: { greater_than: 0 }
    validates :fulfillment_type, presence: true
    validate :valid_fulfillment_period_format, if: :fulfillment_period?

    # Only get fulfillments that are due AND not expired
    scope :due_for_fulfillment, -> {
      where("next_fulfillment_at <= ?", Time.current)
        .where("expires_at IS NULL OR expires_at > ?", Time.current)
    }
    scope :active, -> { where("expires_at IS NULL OR expires_at > ?", Time.current) }

    # Alias for backward compatibility - will be removed in next version
    scope :pending, -> { due_for_fulfillment }

    def recurring?
      fulfillment_period.present?
    end

    def expired?
      expires_at.present? && expires_at <= Time.current
    end

    def active?
      !expired?
    end

    def calculate_next_fulfillment
      return nil unless recurring?
      return nil if next_fulfillment_at.nil?  # Already stopped

      next_fulfillment_at + UsageCredits::PeriodParser.parse_period(fulfillment_period)
    end

    private

    def valid_fulfillment_period_format
      unless UsageCredits::PeriodParser.valid_period_format?(fulfillment_period)
        errors.add(:fulfillment_period, "must be in format like '2.months' or '15.days' and use supported units")
      end
    end
  end
end
