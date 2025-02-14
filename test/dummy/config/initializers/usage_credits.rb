# frozen_string_literal: true

UsageCredits.configure do |config|

  # Default test operations
  operation :small_operation do
    costs 1.credit
  end

  # operation :test_operation do
  #   costs 10.credits + 1.credits_per(:mb)
  #   validate ->(params) { params[:size].to_i <= 100.megabytes }, "File too large (max: 100 MB)"
  # end

  operation :prohibitive_operation do
    costs 1_000_000.credits
  end

  operation :this_operation_will_always_fail do
    costs 42.credits
  end


  # Define test credit packs
  credit_pack :tiny do
    gives 10.credits
    costs 99.cents
  end

  credit_pack :starter do
    gives 1000.credits
    costs 49.dollars
  end

  credit_pack :pro do
    gives 5000.credits
    bonus 100.credits  # Optional: give bonus credits
    costs 199.dollars
    currency :usd
  end


  # Define subscriptions
  subscription_plan :test_plan do
    processor_plan(:fake_processor, "abcdef123456")
    gives 10.credits.every(:month)
    unused_credits :expire
  end

  # Alert when balance drops below 100 credits
  # Set to nil to disable low balance alerts
  # config.low_balance_threshold = 20.credits

  # # Handle low credit balance alerts
  # config.on_low_balance do |user|
  #   # Send notification to user when their balance drops below the threshold
  #   ApplicationMailer.generic_email(to: user.email, body: "Heads up! You're low on credits.", subject: "Low credits alert").deliver_now
  # end

end
