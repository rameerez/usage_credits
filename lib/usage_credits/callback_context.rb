# frozen_string_literal: true

module UsageCredits
  # Immutable context object passed to all callbacks
  # Provides consistent, typed access to event data
  CallbackContext = Struct.new(
    :event,           # Symbol - the event type
    :wallet,          # UsageCredits::Wallet instance
    :amount,          # Integer - credits involved (if applicable)
    :previous_balance, # Integer - balance before operation
    :new_balance,     # Integer - balance after operation
    :threshold,       # Integer - low balance threshold (for low_balance events)
    :category,        # Symbol - transaction category
    :operation_name,  # Symbol - name of the operation
    :transaction,     # UsageCredits::Transaction - the transaction created
    :metadata,        # Hash - additional contextual data
    keyword_init: true
  ) do
    def to_h
      super.compact
    end

    # Convenience: get owner from wallet
    def owner
      wallet&.owner
    end
  end
end
