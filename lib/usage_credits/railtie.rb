# frozen_string_literal: true

require "usage_credits" unless defined?(UsageCredits::Engine)

module UsageCredits
  # Compatibility constant for applications that require this historical path.
  Railtie = Engine unless const_defined?(:Railtie, false)
end
