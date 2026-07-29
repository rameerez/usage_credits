# frozen_string_literal: true

module UsageCredits
  # A transfer records an internal movement of credits between two wallets.
  # The actual balance impact lives in the linked transactions on each side
  # so the transaction history remains explicit.
  #
  # This class extends Wallets::Transfer with usage_credits table configuration.

  class Transfer < Wallets::TransferBase
    # =========================================
    # Embeddability Configuration
    # =========================================

    self.embedded_table_name = "usage_credits_transfers"
    self.config_provider = -> { UsageCredits.configuration }
    self.transaction_class_name = "UsageCredits::Transaction"

    # =========================================
    # Re-declare Associations with Correct Classes
    # =========================================

    belongs_to :from_wallet,
      class_name: "UsageCredits::Wallet",
      inverse_of: :outgoing_transfers,
      optional: false
    belongs_to :to_wallet,
      class_name: "UsageCredits::Wallet",
      inverse_of: :incoming_transfers,
      optional: false
    has_many :transactions,
      class_name: "UsageCredits::Transaction",
      foreign_key: :transfer_id,
      inverse_of: :transfer,
      dependent: :nullify
  end
end
