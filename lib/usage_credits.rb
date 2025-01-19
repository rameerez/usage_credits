# frozen_string_literal: true

require "rails"
require "active_record"
require "pay"

# Require core extensions first
require "usage_credits/core_ext/numeric"

# Require concerns first (needed by models)
require "usage_credits/models/concerns/has_wallet"
require "usage_credits/models/concerns/subscription_extension"

# Require core files
require "usage_credits/version"
require "usage_credits/configuration"

# Define base ApplicationRecord first
module UsageCredits
  class ApplicationRecord < ActiveRecord::Base
    self.abstract_class = true
  end
end

# Require models
require "usage_credits/models/operation"
require "usage_credits/models/pack"
require "usage_credits/models/subscription_rule"
require "usage_credits/models/wallet"
require "usage_credits/models/transaction"

# UsageCredits is a delightful credits system for Rails apps
module UsageCredits
  class Error < StandardError; end
  class InsufficientCredits < Error; end
  class InvalidOperation < Error; end
  class InvalidPack < Error; end

  class << self
    attr_writer :configuration

    def configuration
      @configuration ||= Configuration.new
    end

    def configure
      yield(configuration)
    end

    # More English-like operation definition
    def operation(name, &block)
      builder = Operation::Builder.new(name)
      builder.instance_eval(&block)
      operations[name] = builder.build
    end

    # More English-like credit pack definition
    def credit_pack(name, &block)
      pack = Pack::Builder.new(name)
      pack.instance_eval(&block)
      packs[name] = pack.build
    end

    # More English-like subscription plan definition
    def subscription_plan(name, &block)
      rule = SubscriptionRule.new(name)
      rule.instance_eval(&block)
      subscription_rules[name] = rule
    end

    def operations
      @operations ||= {}
    end

    def packs
      @packs ||= {}
    end

    def subscription_rules
      @subscription_rules ||= {}
    end

    def reset!
      @configuration = nil
      @operations = {}
      @packs = {}
      @subscription_rules = {}
    end
  end
end

# Require Rails integration
require "usage_credits/engine" if defined?(Rails)
require "usage_credits/railtie" if defined?(Rails)

# Make DSL methods available at top level
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
