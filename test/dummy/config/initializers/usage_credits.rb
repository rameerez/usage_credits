# frozen_string_literal: true

UsageCredits.configure do |config|

  operation :test_operation do
    cost 1.credit
  end

  operation :expensive_operation do
    cost 1000.credits
  end

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

  # Example operations (uncomment and modify as needed):
  #
  # operation :send_email do
  #   cost 1.credit
  # end
  #
  # operation :process_image do
  #   cost 10.credits + 0.5.credits_per(:mb)
  #   validate ->(params) { params[:size] <= 100.megabytes }, "File too large"
  # end
  #
  # credit_pack :starter do
  #   includes 1000.credits
  #   bonus 100.credits
  #   costs 49.dollars
  # end
  #
  # subscription_plan :pro do
  #   gives 10_000.credits.per_month
  #   signup_bonus 1_000.credits
  #   trial_includes 500.credits
  #   unused_credits :rollover # or :expire
  # end

  # Define your credit operations here
  # Example:
  # config.operation :send_email, cost: 1
  # config.operation :process_image, cost: 5
  # config.operation :generate_report, cost: 10

  # Optional: Define credit packs for one-time purchases
  # Example:
  # config.credit_pack :starter, credits: 100, price: 9.99
  # config.credit_pack :pro, credits: 500, price: 39.99
  # config.credit_pack :enterprise, credits: 2000, price: 149.99

  # Optional: Define subscription plans with monthly credit allowances
  # Example:
  # config.subscription_plan :basic, credits_per_month: 100, price_per_month: 9.99
  # config.subscription_plan :pro, credits_per_month: 500, price_per_month: 39.99
  # config.subscription_plan :enterprise, credits_per_month: 2000, price_per_month: 149.99

  # Optional: Configure default behavior
  # config.default_starting_credits = 0  # Credits given to new users
  # config.allow_negative_balance = false # Whether to allow operations when user has insufficient credits
  # config.rollover_credits = false      # Whether unused credits roll over to next month for subscription plans
  # config.credit_expiration = 12.months # How long credits are valid for (nil for no expiration)
end
