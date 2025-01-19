# frozen_string_literal: true

UsageCredits.configure do |config|
  # Default currency for credit pack pricing
  config.default_currency = :usd

  # Default threshold for low balance alerts (set to nil to disable)
  config.low_balance_threshold = 100.credits

  # Whether to enable credit balance alerts
  # TODO: fix
  # config.enable_alerts = true

  # Default credit expiration period (nil means no expiration)
  # TODO: fix
  # config.credit_expiration_period = nil

  # Whether to allow negative balances (useful for enterprise customers)
  config.allow_negative_balance = false

  # Customize credit formatting (e.g., "1,000 credits")
  config.format_credits do |amount|
    amount.to_i.to_s
  end

  # Customize credit rounding behavior (:round, :floor, :ceil)
  config.rounding_strategy = :round
end

# Define your credit operations
operation :example_operation do
  # Fixed cost of 10 credits
  cost 10.credits

  # Or dynamic cost based on parameters:
  # cost ->(params) { params[:size] * 0.5.credits_per(:mb) }

  # Optional validation
  validate ->(params) { params[:size] <= 10.megabytes }, "File too large"
end

# Define credit packs that users can purchase
credit_pack :starter do
  includes 1000.credits
  bonus 100.credits
  costs 49.dollars
end

# Define subscription rules for credit allocation
subscription_plan :pro do
  gives 10_000.credits.per_month
  signup_bonus 1_000.credits
  trial_includes 500.credits
  unused_credits :rollover
end
