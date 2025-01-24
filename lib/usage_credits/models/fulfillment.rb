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

      duration = parse_fulfillment_period
      next_fulfillment_at + duration
    end

    private

    def valid_fulfillment_period_format
      # Basic format validation: should be like "2.months", "15.days", etc.
      unless fulfillment_period.match?(/^\d+\.(days?|weeks?|months?|years?)$/)
        errors.add(:fulfillment_period, "must be in format like '2.months' or '15.days'")
      end
    end

    def parse_fulfillment_period
      return nil unless fulfillment_period.present?

      if fulfillment_period =~ /^(\d+)\.(day|days|week|weeks|month|months|year|years)$/
        amount = $1.to_i
        unit = $2.singularize
        amount.send(unit)
      else
        raise ArgumentError, "Invalid fulfillment period format: #{fulfillment_period}"
      end
    end
  end
end
