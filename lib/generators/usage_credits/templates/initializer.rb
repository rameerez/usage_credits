# frozen_string_literal: true

UsageCredits.configure do |config|
  #
  # Minimum fulfillment period for subscription plans (default: 1.day)
  # In development/test, you can set this to a shorter period for faster testing:
  #
  # config.min_fulfillment_period = 2.seconds if Rails.env.development?
  #
  #
  #
  # Define your credit-consuming operations below
  #
  # Example:
  #
  # operation :send_email do
  #   costs 1.credit
  # end
  #
  # operation :process_image do
  #   costs 10.credits + 1.credit_per(:mb)
  #   validate ->(params) { params[:size] <= 100.megabytes }, "File too large"
  # end
  #
  # operation :generate_ai_response do
  #   costs 5.credits
  #   validate ->(params) { params[:prompt].length <= 1000 }, "Prompt too long"
  #   meta category: :ai, description: "Generate AI response"
  # end
  #
  # operation :process_items do
  #   costs 1.credit_per(:units)  # Cost per item processed
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
  #
  #   # Single price (backward compatible)
  #   stripe_price "price_basic_monthly"
  # end
  #
  # subscription_plan :pro do
  #   gives 10_000.credits.every(:month)
  #   signup_bonus 1_000.credits
  #   trial_includes 500.credits
  #   unused_credits :expire  # Credits expire at the end of the fulfillment period (use :rollover to roll over to next period)
  #
  #   # Multi-period pricing (monthly + yearly)
  #   stripe_price month: "price_pro_monthly", year: "price_pro_yearly"
  #
  #   # When creating checkout sessions with multi-period plans, specify the period:
  #   # plan.create_checkout_session(user, success_url: "/success", cancel_url: "/cancel", period: :month)
  #   # plan.create_checkout_session(user, success_url: "/success", cancel_url: "/cancel", period: :year)
  # end
  #
  #
  # === Lifecycle Callbacks ===
  #
  # Hook into credit events for analytics, notifications, and custom logic.
  # All callbacks receive a context object with event-specific data.
  #
  # Available callbacks:
  #   on_credits_added           - After credits are added to a wallet
  #   on_credits_deducted        - After credits are deducted from a wallet
  #   on_low_balance_reached     - When balance drops below threshold (fires once per crossing)
  #   on_balance_depleted        - When balance reaches exactly zero
  #   on_insufficient_credits    - When an operation fails due to insufficient credits
  #   on_credit_pack_purchased   - After a credit pack purchase is fulfilled
  #   on_subscription_credits_awarded - After subscription credits are awarded
  #
  # Context object properties (available depending on event):
  #   ctx.event            # Symbol - the event name
  #   ctx.owner            # The wallet owner (User, Team, etc.)
  #   ctx.wallet           # The UsageCredits::Wallet instance
  #   ctx.amount           # Credits involved
  #   ctx.previous_balance # Balance before the operation
  #   ctx.new_balance      # Balance after the operation
  #   ctx.transaction      # The UsageCredits::Transaction record
  #   ctx.category         # Transaction category (:manual_adjustment, :operation_charge, etc.)
  #   ctx.threshold        # Low balance threshold (for low_balance_reached)
  #   ctx.operation_name   # Operation name (for insufficient_credits)
  #   ctx.metadata         # Additional context-specific data
  #   ctx.to_h             # Convert to hash (excludes nil values)
  #
  # IMPORTANT: Keep callbacks fast! Use background jobs (deliver_later, perform_later) to avoid blocking credit operations.
  #
  # Example: Prompt user to buy more credits when running low
  #
  # config.low_balance_threshold = 100.credits  # Set to nil to disable (default: 100)
  #
  # config.on_low_balance_reached do |ctx|
  #   LowCreditsMailer.buy_more(ctx.owner, remaining: ctx.new_balance).deliver_later
  # end
  #
  # Example: Prompt user to buy credits when they run out:
  # config.on_balance_depleted do |ctx|
  #   OutOfCreditsMailer.buy_more(ctx.owner).deliver_later
  # end
  #
  # Example: Log when users hit credit limits (useful for debugging)
  # config.on_insufficient_credits do |ctx|
  #   Rails.logger.info "[Credits] User #{ctx.owner.id} needs #{ctx.amount}, has #{ctx.metadata[:available]}"
  # end
  #
  # Example: Track credit purchases (replace with your analytics service)
  # config.on_credit_pack_purchased do |ctx|
  #   # e.g., Mixpanel, Amplitude, Segment, PostHog, etc.
  #   YourAnalyticsService.track(ctx.owner.id, "credits_purchased", amount: ctx.amount)
  # end
  #
  #
  #
  # Grace period for credit expiration (default: 5.minutes)
  #
  # This is for how long expiring credits from the previous fulfillment cycle will "overlap" the following fulfillment period.
  # During this time, old credits from the previous period will erroneously count as available balance.
  # But if we set this to 0 or nil, user balance will show up as zero some time until the next fulfillment cycle hits.
  # A good default is to match the frequency of your UsageCredits::FulfillmentJob
  #
  # config.fulfillment_grace_period = 5.minutes
  #
  # NOTE: If your fulfillment period is shorter than the grace period (e.g., credits
  # every 15 seconds with a 5-minute grace), the grace period is AUTOMATICALLY CAPPED
  # to the fulfillment period. This prevents balance accumulation where credits pile
  # up faster than they expire. A warning will be logged during initialization.
  #
  # This is typically only relevant for development/testing with very short periods.
  # In production with monthly/daily fulfillment cycles, the default should work just fine.
  #
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
  #   "#{amount} credits"
  # end
end
