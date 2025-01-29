# 💳✨ `usage_credits` - Add usage-based credits to your Rails app 

[![Gem Version](https://badge.fury.io/rb/usage_credits.svg)](https://badge.fury.io/rb/usage_credits)

> [!CAUTION]
> I'm still developing this. While the overall architecture should be sound and I myself may be using this gem in production for my products, usage-based billing is critical to anyone's business. There may be edge cases I'm not covering. Getting this wrong means either losing money or angry customers. Please help me test this app (test it under your own setup + let's write a solid test suite) so I can remove this warning.

Allow your users to have in-app credits they can use to perform operations.

✨ Perfect for SaaS, AI apps, games, and API products that want to implement usage-based pricing.

Refill user credits with subscriptions, allow your users to purchase booster credit packs, rollover unused credits to the next billing period, and more!

> [!IMPORTANT]
> This gem requires an ActiveJob backend to handle recurring credit fulfillment. Make sure you have one configured (Sidekiq, `solid_queue`, etc.) or subscription credits won't be fulfilled

> [!NOTE]
> `usage_credits` integrates with the [`pay`](https://github.com/pay-rails/pay) gem both to refill credits through subscriptions, and so you can easily sell credit packs through Stripe, Lemon Squeezy, PayPal or any `pay`-supported processor.

---

Your new superpowers:

- Keep track of each user's credits
- Define how many credits any operation in your app costs
- Spend credits securely (credits won't get spent if the operation fails)
- Allow users to purchase credit packs at any time (including mid-billing cycle)
- Refill credits through subscriptions (monthly, yearly, etc.)
- Refill credits at arbitrary periods, decoupled from billing periods (refill credits every day, every month, every quarter, etc.)
- Give users bonus credits (for referrals, trial subscriptions, etc.)
- Handle subscription upgrades and downgrades gracefully
- Rollover credits to the next period
- Handle refunds (partial and total)
- Expire credits after a certain date
- Track every credit transaction with detailed history and audit trail for billing / reporting

All with a simple DSL that reads just like English.

## 👨‍💻 Example

Say you have a `User` model. You add `has_credits` to it and you're ready to go:

```ruby
@user.give_credits(100, reason: "signup")
```

Now you can check the balance:
```ruby
@user.credits
=> 100
```

And perform operations:
```ruby
@user.has_enough_credits_to?(:send_email)
=> true

# You can estimate the total cost before performing the operation
@user.estimate_credits_to(:send_email)
=> 1

# Spend credits
@user.spend_credits_on(:send_email) do
  # actually perform the thing here – no credits will be spent if it fails
end

# Then check the remaining balance
@user.credits  
=> 99
```

This gem keeps track of every transaction and its cost + origin, so you can keep a clean audit trail for clear invoicing and reference / auditing purposes:
```ruby
@user.credit_history.pluck(:category, :amount)
=> [["signup_bonus", 100], ["operation_charge", -1]]
```

Each transaction stores comprehensive metadata about the action that was performed:
```ruby
@user.credit_history.last.metadata
=> {"operation"=>"send_email", "cost"=>1, "params"=>{}, "metadata"=>{}, "executed_at"=>"..."}
```

The `usage_credits` gem also allows you to expire credits, fulfill credits based on monthly / yearly subscriptions, sell one-time booster credit packs, rollover/expire unused credits to the next billing period, and more!

Defining credit subscriptions and credit-spending operations is as simple as:
```ruby
subscription_plan :pro do
  gives 1_000.credits.every :month
  unused_credits :rollover # or :expire
end

operation :send_email do
  costs 1.credit
end
```

Sound good? Let's get started!


## Quick start

Add the gem to your Gemfile:
```ruby
gem 'usage_credits'
```

Then run:
```bash
bundle install
rails generate usage_credits:install
rails db:migrate
```

Add `has_credits` your user model (or any model that needs to have credits):
```ruby
class User < ApplicationRecord
  has_credits
end
```

Lastly, schedule the `UsageCredits::FulfillmentJob` to run periodically (we rely on this ActiveJob job to refill credits for subscriptions). For example, with Solid Queue:

```yaml
# config/recurring.yml

production:
  refill_credits:
    class: UsageCredits::FulfillmentJob
    queue: default
    schedule: every 5 minutes
```

(Your actual setup for the recurring job may change if you're using Sidekiq or other ActiveJob backend – make sure you set it up right for your specific backend)

That's it! Your app now has a credits system. Let's see how to use it.

## How it works

`usage_credits` makes it dead simple to add a usage-based credits system to your Rails app:

1. Users can get credits by:
  - Purchasing credit packs (e.g., "1000 credits for $49")
  - Having a subscription (e.g., "Pro plan includes 10,000 credits/month")

2. Users spend credits on operations you define:
  - "Sending an email costs 1 credit"
  - "Processing an image costs 10 credits + 1 credit per MB"

First, let's see how to define these credit-consuming operations.

## Define credit-consuming operations and set credit costs

Define all your operations and their cost in your `config/initializers/usage_credits.rb` file.

For example, create a simple operation named `send_email` that costs 1 credit to perform:

```ruby
# Simple fixed cost
operation :send_email do
  costs 1.credit
end
```

You can get quite sophisticated in pricing, and define the cost of your operations based on parameters:
```ruby
operation :process_image do
  # Cost based on size
  costs 10.credits + 1.credit_per(:mb)
end
```

> [!NOTE]
> Credit costs must be whole numbers. Decimals are not allowed to avoid floating-point issues and ensure predictable billing.
> ```ruby
> 1.credit              # ✅ Valid: whole number
> 10.credits            # ✅ Valid: whole number
> 1.credits_per(:mb)    # ✅ Valid: whole number rate
> 
> 0.5.credits           # ❌ Invalid: decimal credits
> 1.5.credits_per(:mb)  # ❌ Invalid: decimal rate
> ```
> For variable costs (like per MB), the final cost is rounded according to your configured rounding strategy (defaults to rounding up).
> For example, with `1.credits_per(:mb)`, using 2.3 MB will cost 3 credits by default, to avoid undercharging users.

### Units and Rounding

For variable costs, you can specify units in different ways:

```ruby
# Using megabytes
operation :process_image do
  costs 1.credits_per(:mb)  # or :megabytes, :megabyte
end

# Using units
operation :process_items do
  costs 1.credits_per(:units)  # or :unit
end
```

When using the operation, you can specify the size directly in the unit:
```ruby
# Direct MB specification
@user.estimate_credits_to(:process_image, mb: 5)  # => 5 credits

# Or using byte size (automatically converted)
@user.estimate_credits_to(:process_image, size: 5.megabytes)  # => 5 credits
```

You can configure how fractional costs are rounded:
```ruby
UsageCredits.configure do |config|
  # :ceil (default) - Always round up (2.1 => 3)
  # :floor - Always round down (2.9 => 2)
  # :round - Standard rounding (2.4 => 2, 2.6 => 3)
  config.rounding_strategy = :ceil
end
```

It's also possible to add validations and metadata to your operations:

```ruby
# With custom validation
operation :generate_ai_response do
  costs 5.credits
  validate ->(params) { params[:prompt].length <= 1000 }, "Prompt too long"
end

# With metadata for better tracking
operation :analyze_data do
  costs 20.credits
  meta category: :analytics, description: "Deep data analysis"
end
```

## Spend credits

There's a handy `estimate_credits_to` method to can estimate the total cost of an operation before spending any credits:

```ruby
@user.estimate_credits_to(:process_image, size: 5.megabytes)
=> 15 # (10 base + 5 MB * 1 credit/MB)
```

There's also a `has_enough_credits_to?` method to nicely check the user has enough credits to perform a certain operation:
```ruby
if @user.has_enough_credits_to?(:process_image, size: 5.megabytes)
  # do whatever
else
  redirect_to credits_path, alert: "Not enough credits!"
end
```

Finally, you can actually spend credits with `spend_credits_on`:
```ruby
@user.spend_credits_on(:process_image, size: 5.megabytes)
```

To ensure credits are not subtracted from users during failed operations, you can pass a block to `spend_credits_on`. No credits are spent if the block doesn't succeed (no errors, no exceptions, no raises, etc.) This way, you ensure credits are only spent if the operation succeeds:

```ruby
@user.spend_credits_on(:process_image, size: 5.megabytes) do
  process_image(params)  # If this raises an error, no credits are spent
end
```

If you want to spend the credits immediately, you can use the non-block form:

```ruby
@user.spend_credits_on(:process_image, size: 5.megabytes)
process_image(params)  # If this fails, credits are already spent!
```

> [!TIP]
> Always estimate and check credits before performing expensive operations.
> If validation fails (e.g., file too large), both methods will raise `InvalidOperation`.
> Perform your operation inside the `spend_credits_on` block OR make the credit spend conditional to the actual operation, so users are not charged if the operation fails.

## Sell credit packs

> [!IMPORTANT]
> For all payment-related operations (sell credit packs, handle subscription-based fulfillment, etc. this gem relies on the [`pay`](https://github.com/pay-rails/pay) gem – make sure you have it installed and correctly configured before continuing)

In the `config/initializers/usage_credits.rb` file, define credit packs users can buy:

```ruby
credit_pack :starter do
  gives 1000.credits
  costs 49.dollars
end
```

Then, you can prompt them to purchase it with our `pay`-based helpers:
```ruby
# Create a Stripe Checkout session for purchase
credit_pack = UsageCredits.credit_packs[:starter]
session = credit_pack.create_checkout_session(current_user)
redirect_to session.url
```

The gem automatically handles:
- Credit fulfillment after successful payment
- Proportional credit removal on refunds (e.g., if 50% is refunded, 50% of credits are removed)
- Prevention of double-processing through metadata flags
- Support for multiple currencies (USD, EUR, etc.)
- Detailed transaction tracking with metadata like:
  ```ruby
  {
    credit_pack: "starter",         # Credit pack identifier
    charge_id: "ch_xxx",            # Payment processor charge ID
    processor: "stripe",            # Payment processor used
    price_cents: 4900,              # Amount paid in cents
    currency: "usd",                # Currency used for payment
    credits: 1000,                  # Base credits given
    purchased_at: "2024-01-20"      # Purchase timestamp
  }
  ```

## Low balance alerts

Notify users when they are running low on credits (useful to upsell them a credit pack):

```ruby
UsageCredits.configure do |config|
  # Alert when balance drops below 100 credits
  # Set to nil to disable low balance alerts
  config.low_balance_threshold = 100.credits
  
  # Handle low credit balance alerts
  config.on_low_balance do |user|
    # Send notification to user
    UserMailer.low_credits_alert(user).deliver_later
    
    # Or trigger any other business logic
    SlackNotifier.notify("User #{user.id} is running low on credits!")
  end
end
```

## Subscription plans with credits

Subscription plans have three components:
1. Credits: the amount of credits that will be given eac fulfillment cycle (monthly, quarterly, yearly, etc.)
2. Signup bonus: One-time credits given when subscription becomes active
3. Trial credits: Credits given during trial period
4. What to do with the credits from the previous period: either carry them over to the following period (`:rollover`) or `:expire` them

```ruby
subscription_plan :pro do
  stripe_price "price_XYZ"            # Link it to your Stripe price
  gives 10_000.credits.every(:month)  # Monthly credits
  signup_bonus 1_000.credits          # One-time bonus
  trial_includes 500.credits          # Trial period credits
  unused_credits :rollover            # Credits roll over to the next fulfillment period (:rollover or :expire)
  expire_after 30.days                # Optional: credits expire after cancellation
end
```

### Credit fulfillment

Credit fulfillment is decoupled from billing periods, so you can drip credits at any pace you want (e.g., 100/day instead of 3000/month)

`pay` handles the user's subscription, we handle how we fulfill that subscription.

We rely on ActiveJob to fulfill credits. So you should have an ActiveJob backend installed and configured (Sidekiq, `solid_queue`, etc.) for credits to be refilled.

To make fulfillment actually work, you'll need to schedule the fulfillment job to run periodically, as explained in the setup section.

### Changing subscriptions

When handling plan changes:
- Upgrades cause an immediate reset to the new amount (if not rollover)
- Downgrades maintain existing credits until the next billing cycle
- Trial credits are automatically expired (converted to a negative transaction) if the trial expires without payment
- Unused credits can either roll over (`:rollover`) or expire (`:expire`) at the end of each billing cycle

When a user subscribes to a plan (via the `pay` gem), they'll automatically have their credits refilled.

## Transaction history & audit trail

Every credit transaction is automatically tracked with detailed metadata:

```ruby
# Get recent activity
user.credit_history.recent

# Filter by type
user.credit_history.by_category(:operation_charge)
user.credit_history.by_category(:subscription_credits)

# Audit operation usage
user.credit_history
  .where(category: :operation_charge)
  .where("metadata->>'operation' = ?", 'process_image')
  .where(created_at: 1.month.ago..)
```

Each operation charge includes detailed audit metadata:
```ruby
{
  operation: "process_image",             # Operation name
  cost: 15,                               # Actual cost charged
  params: { size: 1024 },                 # Parameters used
  metadata: { category: "image" },        # Custom metadata
  executed_at: "2024-01-19T16:57:16Z",    # When executed
  gem_version: "1.0.0"                    # Gem version
}
```

This makes it easy to:
- Track historical costs
- Audit operation usage
- Generate detailed invoices
- Monitor usage patterns

## Advanced usage

### Numeric extensions

The gem adds several convenient methods to Ruby's `Numeric` class to make the DSL read naturally:

```ruby
# Credit amounts
1.credit      # => 1 credit
10.credits    # => 10 credits

# Pricing
49.dollars    # => 4900 cents (for Stripe)

# Sizes and rates
1.credits_per(:mb)  # => 1 credit per megabyte
100.megabytes      # => 100 MB (uses Rails' numeric extensions)
```

### Custom credit formatting

```ruby
UsageCredits.configure do |config|
  # Format as "1,000 credits remaining"
  config.format_credits do |amount|
    "#{number_with_delimiter(amount)} credits remaining"
  end
end
```

### Rounding strategy

Configure how credit costs are rounded:

```ruby
UsageCredits.configure do |config|
  # :ceil (default) - Always round up (2.1 => 3)
  # :floor - Always round down (2.9 => 2)
  # :round - Standard rounding (2.4 => 2, 2.6 => 3)
  config.rounding_strategy = :ceil
end
```

## Testing

Run the test suite with `bundle exec rake test`

## Development

After checking out the repo, run `bin/setup` to install dependencies. Then, run `rake spec` to run the tests. You can also run `bin/console` for an interactive prompt that will allow you to experiment.

To install this gem onto your local machine, run `bundle exec rake install`.

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/rameerez/usage_credits. Our code of conduct is: just be nice and make your mom proud of what 
you do and post online.

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).
