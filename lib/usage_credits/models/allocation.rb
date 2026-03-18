# frozen_string_literal: true

module UsageCredits
  # An Allocation links a *negative* (spend) transaction
  # to a *positive* (credit) transaction, indicating how many
  # credits were taken from that specific credit source.
  #
  # This class extends Wallets::Allocation with usage_credits table configuration.

  class Allocation < Wallets::Allocation
    # =========================================
    # Embeddability Configuration
    # =========================================

    self.embedded_table_name = "usage_credits_allocations"
    self.config_provider = -> { UsageCredits.configuration }

    # =========================================
    # Re-declare Associations with Correct Classes
    # =========================================

    belongs_to :spend_transaction, class_name: "UsageCredits::Transaction", foreign_key: "transaction_id"
    belongs_to :source_transaction, class_name: "UsageCredits::Transaction"
  end
end
