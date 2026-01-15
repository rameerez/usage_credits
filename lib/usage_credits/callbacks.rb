# frozen_string_literal: true

module UsageCredits
  # Centralized callback dispatch module
  # Handles executing callbacks with error isolation
  module Callbacks
    module_function

    # Dispatch a callback event with error isolation
    # Callbacks should never break the main operation
    #
    # @param event [Symbol] The event type (e.g., :credits_added, :low_balance_reached)
    # @param context_data [Hash] Data to pass to the callback via CallbackContext
    def dispatch(event, **context_data)
      config = UsageCredits.configuration
      callback = config.public_send(:"on_#{event}_callback")

      return unless callback.is_a?(Proc)

      context = CallbackContext.new(event: event, **context_data)

      execute_safely(callback, context)
    end

    # Execute callback with error isolation and arity handling
    #
    # @param callback [Proc] The callback to execute
    # @param context [CallbackContext] The context to pass
    def execute_safely(callback, context)
      case callback.arity
      when 1, -1, -2  # Accepts one arg or variable args
        callback.call(context)
      when 0
        callback.call
      else
        log_warn "[UsageCredits] Callback has unexpected arity (#{callback.arity}). Expected 0 or 1."
      end
    rescue StandardError => e
      # Log but don't re-raise - callbacks should never break credit operations
      log_error "[UsageCredits] Callback error for #{context.event}: #{e.class}: #{e.message}"
      log_debug e.backtrace.join("\n")
    end

    # Safe logging that works with or without Rails
    def log_error(message)
      if defined?(Rails) && Rails.respond_to?(:logger) && Rails.logger
        Rails.logger.error(message)
      else
        warn message
      end
    end

    def log_warn(message)
      if defined?(Rails) && Rails.respond_to?(:logger) && Rails.logger
        Rails.logger.warn(message)
      else
        warn message
      end
    end

    def log_debug(message)
      if defined?(Rails) && Rails.respond_to?(:logger) && Rails.logger&.debug?
        Rails.logger.debug(message)
      end
    end
  end
end
