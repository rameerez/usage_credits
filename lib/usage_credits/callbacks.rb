# frozen_string_literal: true

module UsageCredits
  # usage_credits adapter for wallets' shared callback dispatcher.
  module Callbacks
    extend Wallets::CallbackDispatcher

    module_function

    def callback_configuration
      UsageCredits.configuration
    end

    def callback_context_class
      UsageCredits::CallbackContext
    end

    def callback_log_prefix
      "[UsageCredits]"
    end
  end
end
