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
    validates :source_id, uniqueness: { scope: :source_type }, if: :source_id?
    validates :credits_last_fulfillment, presence: true, numericality: { only_integer: true }
    validates :fulfillment_type, presence: true
    validate :valid_fulfillment_period_format, if: :fulfillment_period?
    validates :next_fulfillment_at, comparison: { greater_than: :last_fulfilled_at },
      if: -> { recurring? && last_fulfilled_at.present? && next_fulfillment_at.present? }

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

      # If next_fulfillment_at is in the past (e.g. due to missed fulfillments or errors),
      # we use current time as the base to avoid scheduling multiple rapid fulfillments.
      # This ensures smooth recovery from missed fulfillments by scheduling the next one
      # from the current time rather than the missed fulfillment time.
      base_time = next_fulfillment_at > Time.current ? next_fulfillment_at : Time.current

      base_time + UsageCredits::PeriodParser.parse_period(fulfillment_period)
    end

    private

    # Sync in-place modifications to the cached metadata back to the attribute
    # This ensures changes like `metadata["key"] = "value"` are persisted on save
    # Also ensures metadata is never null for MySQL compatibility (JSON columns can't have defaults)
    def sync_metadata_cache
      if @indifferent_metadata
        write_attribute(:metadata, @indifferent_metadata.to_h)
      elsif read_attribute(:metadata).nil?
        write_attribute(:metadata, {})
      end
    end

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
