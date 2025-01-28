# frozen_string_literal: true

# UsageCredits provides a credits system for your application.
# This is the entry point to the gem.

require "rails"
require "active_record"
require "pay"
require "active_support/all"

# Load order matters! Dependencies are loaded in this specific order:
#
# 1. Core helpers
require "usage_credits/helpers/credit_calculator"   # Centralized credit rounding
require "usage_credits/helpers/period_parser"       # Parse fulfillment periods like `:monthly` to `1.month`
require "usage_credits/core_ext/numeric"            # Numeric extension to write `10.credits` in our DSL

# 2. Cost calculation
require "usage_credits/cost/base"
require "usage_credits/cost/fixed"
require "usage_credits/cost/variable"
require "usage_credits/cost/compound"

# 3. Model concerns (needed by models)
require "usage_credits/models/concerns/has_wallet"
require "usage_credits/models/concerns/pay_subscription_extension"
require "usage_credits/models/concerns/pay_charge_extension"

# 4. Core functionality
require "usage_credits/version"
require "usage_credits/configuration"  # Single source of truth for all configuration in this gem

# 5. Shim Rails classes so requires don't break
module UsageCredits
  class ApplicationRecord < ActiveRecord::Base
    self.abstract_class = true
  end

  class ApplicationJob < ActiveJob::Base
  end
end

# 6. Models (order matters for dependencies)
require "usage_credits/models/wallet"
require "usage_credits/models/transaction"
require "usage_credits/models/allocation"
require "usage_credits/models/operation"
require "usage_credits/models/fulfillment"
require "usage_credits/models/credit_pack"
require "usage_credits/models/credit_subscription_plan"

# 7. Jobs
require "usage_credits/services/fulfillment_service.rb"
require "usage_credits/jobs/fulfillment_job.rb"

# Main module that serves as the primary interface to the gem.
# Most methods here delegate to Configuration, which is the single source of truth for all config in the initializer
module UsageCredits
  # Custom error classes
  class Error < StandardError; end
  class InsufficientCredits < Error; end
  class InvalidOperation < Error; end

  class << self
    attr_writer :configuration

    def configuration
      @configuration ||= Configuration.new
    end

    # Configure the gem with a block (main entry point)
    def configure
      yield(configuration)
    end

    # Reset configuration to defaults (mainly for testing)
    def reset!
      @configuration = nil
    end

    # DSL methods - all delegate to configuration
    # These enable things like both `UsageCredits.credit_pack` and bare `credit_pack` usage

    def operation(name, &block)
      configuration.operation(name, &block)
    end

    def operations
      configuration.operations
    end

    def credit_pack(name, &block)
      configuration.credit_pack(name, &block)
    end

    def credit_packs
      configuration.credit_packs
    end
    alias_method :packs, :credit_packs

    def find_credit_pack(name)
      credit_packs[name.to_sym]
    end
    alias_method :find_pack, :find_credit_pack

    def available_credit_packs
      credit_packs.values.uniq
    end
    alias_method :available_packs, :available_credit_packs

    def subscription_plan(name, &block)
      configuration.subscription_plan(name, &block)
    end

    def credit_subscription_plans
      configuration.credit_subscription_plans
    end
    alias_method :subscription_plans, :credit_subscription_plans
    alias_method :plans, :credit_subscription_plans

    def find_subscription_plan(name)
      credit_subscription_plans[name.to_sym]
    end
    alias_method :find_plan, :find_subscription_plan

    def find_subscription_plan_by_processor_id(processor_id)
      configuration.find_subscription_plan_by_processor_id(processor_id)
    end
    alias_method :find_plan_by_id, :find_subscription_plan_by_processor_id

    # Event handling for low balance notifications
    def notify_low_balance(owner)
      return unless configuration.low_balance_callback
      configuration.low_balance_callback.call(owner)
    end

    def handle_event(event, **params)
      case event
      when :low_balance_reached
        notify_low_balance(params[:wallet].owner)
      end
    end

  end
end

# Rails integration
require "usage_credits/engine" if defined?(Rails)
require "usage_credits/railtie" if defined?(Rails)

# Make DSL methods available at top level
# This is what enables the "bare" DSL syntax in initializers. Without it, users would have to write things like
#   UsageCredits.credit_pack :starter do
# instead of
#   credit_pack :starter do
#
# Note: This modifies the global Kernel module, which is a powerful but invasive approach.
module Kernel
  def operation(name, &block)
    UsageCredits.operation(name, &block)
  end

  def credit_pack(name, &block)
    UsageCredits.credit_pack(name, &block)
  end

  def subscription_plan(name, &block)
    UsageCredits.subscription_plan(name, &block)
  end
end
