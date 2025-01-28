# frozen_string_literal: true

UsageCredits.configure do |config|
  #
  # Define your credit-consuming operations below
  #
  # Example:
  #
  # operation :send_email do
  #   cost 1.credit
  # end
  #
  # operation :process_image do
  #   cost 10.credits + 1.credit_per(:mb)
  #   validate ->(params) { params[:size] <= 100.megabytes }, "File too large"
  # end
  #
  # operation :generate_ai_response do
  #   cost 5.credits
  #   validate ->(params) { params[:prompt].length <= 1000 }, "Prompt too long"
  #   meta category: :ai, description: "Generate AI response"
  # end
  #
  # operation :process_items do
  #   cost 1.credit_per(:units)  # Cost per item processed
  #   meta category: :batch, description: "Process items in batch"
  # end
  #
  #
  #
  # Example credit packs (uncomment and modify as needed):
  #
  # credit_pack :tiny do
  #   gives 100.credits
  #   costs 99.cents # Price can be in cents or dollars
  # end
  #
  # credit_pack :starter do
  #   gives 1000.credits
  #   bonus 100.credits  # Optional bonus credits
  #   costs 49.dollars
  # end
  #
  # credit_pack :pro do
  #   gives 5000.credits
  #   bonus 1000.credits
  #   costs 199.dollars
  # end
  #
  #
  #
  # Example subscription plans (uncomment and modify as needed):
  #
  # subscription_plan :basic do
  #   gives 1000.credits.every(:month)
  #   signup_bonus 100.credits
  #   unused_credits :expire  # Credits reset each month
  # end
  #
  # subscription_plan :pro do
  #   gives 10_000.credits.every(:month)
  #   signup_bonus 1_000.credits
  #   trial_includes 500.credits
  #   unused_credits :rollover  # Credits roll over to next month
  # end
  #
  #
  #
  # Alert when balance drops below this threshold (default: 100 credits)
  # Set to nil to disable low balance alerts
  #
  # config.low_balance_threshold = 100.credits
  #
  #
  # Handle low credit balance alerts
  #
  # config.on_low_balance do |user|
    # Send notification to user when their balance drops below the threshold
    # UserMailer.low_credits_alert(user).deliver_later
  # end
  #
  #
  # Rounding strategy for credit calculations (default: :ceil)
  # :ceil - Always round up (2.1 => 3)
  # :floor - Always round down (2.9 => 2)
  # :round - Standard rounding (2.4 => 2, 2.6 => 3)
  #
  # config.rounding_strategy = :ceil
  #
  #
  # Format credits for display (default: "X credits")
  #
  # config.format_credits do |amount|
  #   "#{number_with_delimiter(amount)} credits remaining"
  # end
end
