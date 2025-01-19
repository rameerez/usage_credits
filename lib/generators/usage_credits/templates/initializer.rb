# frozen_string_literal: true

UsageCredits.configure do |config|
  # Allow negative credit balance (default: false)
  # config.allow_negative_balance = false

  # Enable low balance alerts (default: true)
  # config.enable_alerts = true

  # Rounding strategy for credit calculations (default: :round)
  # config.rounding_strategy = :round # or :floor, :ceil

  # Handle events (balance changes, low balance alerts, etc.)
  # config.event_handler = ->(event, **params) do
  #   case event
  #   when :low_balance_reached
  #     # Send notification to user
  #     UserMailer.low_credits_alert(params[:wallet].owner).deliver_later
  #   end
  # end
end

# Define your credit operations
operation :send_email do
  cost 1.credit
end

# operation :process_image do
#   cost 10.credits + 0.5.credits_per(:mb)
#   validate ->(params) { params[:size] <= 100.megabytes }, "File too large"
# end

# Define credit packs users can purchase
credit_pack :starter do
  includes 1000.credits
  bonus 100.credits
  costs 49.dollars
end

# Define subscription plans that give credits
subscription_plan :pro do
  gives 10_000.credits.per_month
  signup_bonus 1_000.credits
  trial_includes 500.credits
  unused_credits :rollover # or :expire
end
