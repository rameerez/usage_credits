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
    validates :credits_last_fulfillment, presence: true, numericality: { only_integer: true }
    validates :fulfillment_type, presence: true
    validate :valid_fulfillment_period_format, if: :fulfillment_period?
    validates :next_fulfillment_at, comparison: { greater_than: :last_fulfilled_at },
      if: -> { recurring? && last_fulfilled_at.present? && next_fulfillment_at.present? }

    # Only get fulfillments that are due AND not stopped
    scope :due_for_fulfillment, -> {
      where("next_fulfillment_at <= ?", Time.current)
        .where("stops_at IS NULL OR stops_at > ?", Time.current)
        .where("last_fulfilled_at IS NULL OR next_fulfillment_at > last_fulfilled_at")
    }
    scope :active, -> { where("stops_at IS NULL OR stops_at > ?", Time.current) }

    # Alias for backward compatibility - will be removed in next version
    scope :pending, -> { due_for_fulfillment }

    def due_for_fulfillment?
      return false unless next_fulfillment_at.present?
      return false if stopped?
      return false if last_fulfilled_at.present? && next_fulfillment_at <= last_fulfilled_at

      next_fulfillment_at <= Time.current
    end

    def recurring?
      fulfillment_period.present?
    end

    def stopped?
      stops_at.present? && stops_at <= Time.current
    end

    def active?
      !stopped?
    end

    def calculate_next_fulfillment
      return nil unless recurring?
      return nil if stopped?
      return nil if next_fulfillment_at.nil?

      next_fulfillment_at + UsageCredits::PeriodParser.parse_period(fulfillment_period)
    end

    private

    def valid_fulfillment_period_format
      unless UsageCredits::PeriodParser.valid_period_format?(fulfillment_period)
        errors.add(:fulfillment_period, "must be in format like '2.months' or '15.days' and use supported units")
      end
    end

    validate :validate_fulfillment_schedule

    def validate_fulfillment_schedule
      return unless next_fulfillment_at.present?

      if recurring?
        # For recurring fulfillments, next_fulfillment_at should be in the future when created
        if new_record? && next_fulfillment_at <= Time.current
          errors.add(:next_fulfillment_at, "must be in the future for new recurring fulfillments")
        end
      else
        # For one-time fulfillments, next_fulfillment_at should be nil
        errors.add(:next_fulfillment_at, "should be nil for non-recurring fulfillments") unless new_record?
      end
    end

  end
end
