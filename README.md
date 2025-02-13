# 💳✨ `usage_credits` - Add usage-based credits to your Rails app 

[![Gem Version](https://badge.fury.io/rb/usage_credits.svg)](https://badge.fury.io/rb/usage_credits)

Allow your users to have in-app credits / tokens they can use to perform operations.

✨ Perfect for SaaS, AI apps, games, and API products that want to implement usage-based pricing.

Refill user credits with Stripe subscriptions, allow your users to top up by purchasing booster credit packs at any time, rollover unused credits to the next billing period, expire credits, implement PAYG (pay-as-you-go) billing, award free credits as bonuses (for referrals, giving feedback, etc.), get a detailed history and audit trail of every transaction for billing / reporting, and more!

All with a simple DSL that reads just like English.

**Requirements**

- An ActiveJob backend (Sidekiq, `solid_queue`, etc.) for subscription credit fulfillment
- [`pay`](https://github.com/pay-rails/pay) gem for Stripe/PayPal/Lemon Squeezy integration (sell credits, refill subscriptions)

## 👨‍💻 Example

`usage_credits` allows you to add credits to your Rails app in just one line of code. If you have a `User` model, just add `has_credits` to it and you're ready to go:

```ruby
class User
  has_credits
end
```

With that, your users automatically get all credits functionality, and you can start performing operations:

```ruby
@user.give_credits(100)
```

You can check any user's balance:
```ruby
@user.credits
=> 100
```

And spend their credits securely:
```ruby
@user.spend_credits_on(:send_email) do
  # Perform the actual operation here.
  # No credits will be spent if this block fails.
end
```

Defining credit-spending operations is as simple as:
```ruby
operation :send_email do
  costs 1.credit
end
```

And defining credit-fulfilling subscriptions is really simple too:
```ruby
subscription_plan :pro do
  gives 1_000.credits.every :month
  unused_credits :rollover # or :expire
end
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

You can also expire credits, fulfill credits based on Stripe subscriptions, sell one-time booster credit packs, rollover/expire unused credits to the next fulfillment period, and more!

Sounds good? Let's get started!

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

> [!IMPORTANT]
> This gem requires an ActiveJob backend to handle recurring credit fulfillment. Make sure you have one configured (Sidekiq, `solid_queue`, etc.) or subscription credits won't be fulfilled.

That's it! Your app now has a credits system. Let's see how to use it.

## How it works

`usage_credits` makes it dead simple to add a usage-based credits system to your Rails app:

1. Users can get credits by:
  - Purchasing credit packs (e.g., "1000 credits for $49")
  - Having a subscription (e.g., "Pro plan includes 10,000 credits/month")
  - Arbitrary bonuses at any point (completing signup, referring a friend, etc.)

2. Users spend credits on operations you define:
  - "Sending an email costs 1 credit"
  - "Processing an image costs 10 credits + 1 credit per MB"

First, let's see how to define these credit-consuming operations.

## Define credit-consuming operations and set credit costs

Define all your operations and their cost in your `config/initializers/usage_credits.rb` file.

For example, create a simple operation named `send_email` that costs 1 credit to perform:

```ruby
operation :send_email do
  costs 1.credit
end
```

You can get quite sophisticated in pricing, and define the cost of your operations based on parameters:
```ruby
operation :process_image do
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

By default, we round up (`:ceil`) all credit costs to avoid undercharging. So if an operation costs 1 credit per megabyte, and the user submits a file that's 5.2 megabytes, we'll deduct 6 credits from the user's wallet.

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

There's also a `has_enough_credits_to?` method to nicely check the user has enough credits before performing a certain operation:
```ruby
if @user.has_enough_credits_to?(:process_image, size: 5.megabytes)
  # actually spend the credits
else
  redirect_to credits_path, alert: "Not enough credits!"
end
```

Finally, you can actually spend credits with `spend_credits_on`:
```ruby
@user.spend_credits_on(:process_image, size: 5.megabytes)
```

To ensure credits are not subtracted from users during failed operations, you can pass a block to `spend_credits_on`. No credits are spent if the block doesn't succeed (it shouldn't raise any exceptions or throw any errors) This way, you ensure credits are only spent if the operation succeeds:

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

## Low balance alerts

You can hook on to our low balance event to notify users when they are running low on credits (useful to upsell them a credit pack):

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

## Award bonus credits

You might want to award bonus credits to your users for arbitrary actions at any point, like referring a friend, completing signup, or any other reason.

To do that, you can just do:

```ruby
@user.give_credits(100, reason: "referral")
```

And the user will get the credits with the proper category in the transaction ledger (so bonus credits get differentiated from purchases / subscriptions for audit trail purposes)

Providing a reason for giving credits is entirely optional (it just helps you if you need to use or analyze the audit trail) – if you don't specify any reason, `:manual_adjustment` is the default reason.

You can also give credits with arbitrary expiration dates:
```ruby
@user.give_credits(100, expires_at: 1.month.from_now)
```

So you can expire any batch of credits at any date in the future.


## Sell credit packs

> [!IMPORTANT]
> For all payment-related operations (sell credit packs, handle subscription-based fulfillment, etc.) this gem relies on the [`pay`](https://github.com/pay-rails/pay) gem – make sure you have it installed and correctly configured with your payment processor (Stripe, Lemon Squeezy, PayPal, etc.) before continuing. Follow the `pay` README for more information and installation instructions.

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
credit_pack = UsageCredits.find_credit_pack(:starter)
session = credit_pack.create_checkout_session(current_user)
redirect_to session.url
```

The gem automatically handles:
- Credit pack fulfillment after successful payment
- Proportional credit removal on refunds (e.g., if 50% is refunded, 50% of credits are removed)
- Prevention of double-processing of purchase
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

## Subscription plans that grant credits

Users can subscribe to a plan (monthly, yearly, etc.) that gives them credits.

Defining a subscription plan is as simple as this:
```ruby
subscription_plan :pro do
  stripe_price "price_XYZ"            # Link it to your Stripe price ID
  gives 10_000.credits.every(:month)  # Monthly credits
  signup_bonus 1_000.credits          # One-time bonus
  trial_includes 500.credits          # Trial period credits
  unused_credits :rollover            # Credits roll over to the next fulfillment period (:rollover or :expire)
  expire_after 30.days                # Optional: credits expire after cancellation
end
```

The first thing to understand is that **credit fulfillment** is decoupled from **billing periods**:

### Credit fulfillment cycles

Credit fulfillment is completely decoupled from billing periods.

This means you can drip credits at any pace you want (e.g., 100/day instead of 3000/month) – and that's completely independent of when your users get actually charged (typically on a monthly or yearly basis, as you defined on Stripe)

`pay` handles the user's subscription payments (billing periods), we handle how we fulfill that subscription (fulfilling cycles)

We rely on ActiveJob to fulfill credits. So you should have an ActiveJob backend installed and configured (Sidekiq, `solid_queue`, etc.) for credits to be refilled. To make fulfillment actually work, you'll need to schedule the fulfillment job to run periodically, as explained in the setup section.

### First, create a Stripe subscription

`usage_credits` relies on you first creating a subscription on your Stripe dashboard and then linking it to the gem by setting the specific Stripe plan ID in the subscription config using the `stripe_price` option, like this:
```ruby
subscription_plan :pro do
  stripe_price "price_XYZ"
  # ...
end
```

For now, only Stripe subscriptions are supported (contribute to the codebase to help us add more payment processors!)

### Specify a fulfillment period

Next, specify how many credits a user subscribed to this plan gets, and when they get them.

Since fulfillment cycles are decoupled from billing cycles, you can either match fulfillment cycles to billing cycles (that is, charge your users every month AND fulfill them every month too, to keep things simple) OR you can specify something else like refill credits every `:day`, every `:quarter`, every `15.days`, every `:year` etc.

```ruby
subscription_plan :pro do
  gives 10_000.credits.every(15.days)
  # or, another example:
  # gives 10_000.credits.every(:quarter)
  # ...
end
```

### Expire or rollover unused credits

At the end of the fulfillment cycle, you can either:
 - Expire all unused credits (so the user starts with X fixed amount of credits every period, and all of them expire at the end of the period, whether they've used them or not)
 - Carry unused credits over to the next period

Just set `unused_credits` to either `:expire` or `:rollover`

```ruby
subscription_plan :pro do
  unused_credits :expire # or :rollover
  # ...
end
```

## Transaction history & audit trail

Every transaction (whether adding or deducting credits) is logged in the ledger, and automatically tracked with metadata:

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
- Audit operation usage
- Generate detailed invoices
- Monitor usage patterns

### Custom credit formatting

A minor thing, but if you want to use the `@transaction.formatted_amount` helper, you can specify the format:

```ruby
UsageCredits.configure do |config|
  config.format_credits do |amount|
    "#{amount} tokens"
  end
end
```

Which will get you:
```ruby
@transaction.formatted_amount
# => "42 tokens"
```

It's useful if you want to name your credits something else (tokens, virtual currency, tasks, in-app gems, whatever) and you want the name to be consistent.

## Technical notes on architecture and how this gem is built

Building a usage credits system is deceptively complex.

The first naive approach is to think this whole thing can be implemented as just a `balance` attribute in the database, a number that you update whenever the user buys or spends credits.

That results in a plethora of bugs as soon as time starts rolling and customers start upgrading, downgrading, and cancelling subscriptions. Customers won't get what they paid for, and you'll always have problems. You always feel like repairing a leaking budget. So you may be tempted to offload all the credit-fulfilling logic to Stripe webhooks and such.

That only gets you so far.

One problem is the discrepancy between billing periods and fulfillment cycles (you may want to charge your users up front for a whole year if they have a yearly subscription, but you may not want to refill all their credits up front, but month by month) Then if you want expiring credits (so that unused credits don't roll over to the next period), credit packs, etc. you essentially end up needing to build a double-entry ledger system. You need to keep track of every credit-giving and credit-spending operation. The ledger should be immutable by design (append-only), transactions should happen on row-level locks to prevent double-spending, operations should be atomic, etc.

That's exactly what I ended up building:
- `Wallet` is the root of all functionality. All users have a wallet that centralizes everything and keeps track of the available balance – and all credit operations (add/deduct credits) are performed on the wallet.
- `Transaction` - operations get logged as transactions. The Transaction model is the basis for the ledger system.
- `Fulfillment` represents a credit-giving action (wether recurring or not). Subscriptions are tied to a Fulfillment record that orchestrates when the actual credit fulfillment should happen, and how often. A Fulfillment object will create one or many positive Transactions.
- `Allocation` is the basis for our bucket-based FIFO credit spending system. It's what solves the [dragging cost problem](https://x.com/rameerez/status/1884246492837302759) and allows for expiring credits.
- `CreditPack` and `CreditSubscriptionPlan` are POROs that model credit-giving objects (one-time purchases for credit packs; recurring subscriptions for subscription plans). They allow for easy configuration through the DSL and store all information on memory.
- `Operation` represents a credit-spending operation.

### Row-level locks

Heads up: we acquire a row-level lock when spending credits, to avoid concurrency inconsistencies. This means the row will be locked for as long as the credit-spending operation lasts. If the block is short (which 99% of the time it is – like updating a record, sending an email, etc.), you’re golden. If someone tries to do 2 minutes of CPU-bound AI generation under that lock, concurrency for that user’s wallet is blocked. Possibly that’s what we want in any case, but it’s something you should know for large tasks.

### Summary of features

**Core ledger:**
- Immutable ledger design (transactions are append-only)
- Row-level locks to prevent double-spending even with concurrent usage
- Secure credit spending (credits will not be deducted if the operation fails)
- Audit trail / transaction logs (each transaction has metadata on how the credits were spent, and what "credit bucket" they drew from)
- Avoids floating-point issues by enforcing integer-only operations

**Billing system:**
- Integrates with `pay` loosely enough not to rely on a single payment processor (we use Pay::Charge and Pay::Subscription model callbacks, not payment-processor-specific webhooks)
- Handles total and partial refunds
- Deals with new subscriptions and cancellations
- One-time credit packs can be bought at any time, independent of subscriptions

**Credit fulfillment system:**
- Credits can be fulfilled at arbitrary periods, decoupled from billing cycles
- Credits can be expired
- Credits can be rolled over to the next period
- Prevents double-fulfillment of credits
- FIFO bucketed ledger approach for credit spending

### Numeric extensions

The gem adds several convenient methods to Ruby's `Numeric` class to make the DSL read naturally:

```ruby
# Credit amounts
1.credit      # => 1 credit
10.credits    # => 10 credits

# Pricing
49.dollars    # => 4900 cents (for Stripe)
29.euros      # => 2900 cents (for Stripe)
99.cents      # =>   99 cents (for Stripe)

# Sizes and rates
1.credit_per(:mb)     # => 1 credit per megabyte
2.credits_per(:unit)  # => 2 credits per unit
100.megabytes         # => 100 MB (uses Rails' numeric extensions)
```

### Kernel extensions

This gem _pollutes_ a bit the `Kernel` namespace by defining 3 top-level methods: `operation`, `credit_pack`, and `credit_subscription`. We do this to have a DSL that reads like plain English. I think the benefits of having these methods outweight the downsides, and there's a low chance of name collision, but in any case it's important you know they're there.


## Edge cases

Billing systems are extremely complex and full of edge cases. This is a new gem, and it may be missing some edge cases.

Real billing systems usually find edge cases when handling things like:
- Prorated changes
- Different pricing tiers
- Usage rollups and aggregation
- Upgrading and downgrading subscriptions
- Pausing and resuming subscriptions (especially at edge times)
- Re-activating subscriptions
- Refunds and credits
- Failed payments
- Usage caps

Please help us by contributing to add tests to cover all critical paths!

## TODO

- [ ] Write a comprehensive `minitest` test suite that covers all critical paths (both happy paths and weird edge cases)
- [ ] Handle subscription upgrades and downgrades (upgrade immediately; downgrade at end of billing period? Cover all scenarios allowed by the Stripe Customer Portal?)

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
