# frozen_string_literal: true

module UsageCredits
  # An Allocation links a *negative* (spend) transaction
  # to a *positive* (credit) transaction, indicating how many
  # credits were taken from that specific credit source.
  #
  # Allocations are the basis for the bucket-based, FIFO-with-expiration inventory-like system
  # This is critical for calculating balances when there are mixed expiring and non-expiring credits
  # Otherwise, balance calculations will always be wrong because negative transactions get dragged forever
  # More info: https://x.com/rameerez/status/1884246492837302759
  class Allocation < ApplicationRecord
    self.table_name = "usage_credits_allocations"

    belongs_to :spend_transaction, class_name: "UsageCredits::Transaction", foreign_key: "transaction_id"
    belongs_to :source_transaction, class_name: "UsageCredits::Transaction"

    validates :amount, presence: true, numericality: { only_integer: true, greater_than: 0 }

    validate :allocation_does_not_exceed_remaining_amount

    private

    def allocation_does_not_exceed_remaining_amount
      return if amount.blank? || source_transaction.blank?

      if source_transaction.remaining_amount < amount
        errors.add(:amount, "exceeds the remaining amount of the source transaction")
      end
    end

  end
end
