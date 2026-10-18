# frozen_string_literal: true

module UsageCredits
  # Normalizes and validates metadata before it crosses a payment-processor
  # boundary. Stripe stores metadata as at most 50 string key/value pairs;
  # structured Ruby values are encoded as one JSON string instead of becoming
  # unsupported nested form parameters.
  module ProcessorMetadata
    MAX_PAIRS = 50
    MAX_KEY_LENGTH = 40
    MAX_VALUE_LENGTH = 500

    module_function

    def normalize(value)
      hash = value.nil? ? {} : value.to_h
      raise ArgumentError, "Processor metadata cannot contain more than #{MAX_PAIRS} keys" if hash.size > MAX_PAIRS

      hash.each_with_object(ActiveSupport::HashWithIndifferentAccess.new) do |(key, raw_value), normalized|
        normalized_key = key.to_s
        validate_key!(normalized_key)

        normalized_value = structured?(raw_value) ? ActiveSupport::JSON.encode(raw_value) : raw_value.to_s
        if normalized_value.length > MAX_VALUE_LENGTH
          raise ArgumentError, "Processor metadata value for #{normalized_key.inspect} exceeds #{MAX_VALUE_LENGTH} characters"
        end

        normalized[normalized_key] = normalized_value
      end
    rescue NoMethodError, TypeError
      raise ArgumentError, "Processor metadata must be hash-like"
    end

    def validate_key!(key)
      if key.empty? || key.length > MAX_KEY_LENGTH || key.match?(/[\[\]]/)
        raise ArgumentError, "Invalid processor metadata key: #{key.inspect}"
      end
    end
    private_class_method :validate_key!

    def structured?(value)
      value.is_a?(Hash) || value.is_a?(Array)
    end
    private_class_method :structured?
  end
end
