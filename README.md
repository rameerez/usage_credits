# 💳 `usage_credits` - Add a usage-based credits system to your Rails app

[![Gem Version](https://badge.fury.io/rb/usage_credits.svg)](https://badge.fury.io/rb/usage_credits)

Allow your users to have credits they can use to perform operations.

Perfect for SaaS, AI apps, and API products that want to implement usage-based pricing.

`usage_credits` integrates with the `pay` gem both to refill credits through subscriptions, and so you can easily sell credit packs through Stripe, Lemon Squeezy, PayPal or any `pay`-supported processor.

With `usage_credits`, you can:
- Keep track of each user's credits
- Define how many credits any operation in your app costs
- Create and sell credit packs
- Refill credits through subscriptions (monthly, yearly, etc.)
- Track every credit transaction with detailed history and audit trail

All with a simple DSL that reads just like English.

## How it works

`usage_credits` makes it dead simple to add a usage-based credits system to your Rails app:

1. Users can get credits by:
   - Purchasing credit packs (e.g., "1000 credits for $49")
   - Having a subscription (e.g., "Pro plan includes 10,000 credits/month")
   - Getting bonuses (e.g., "100 free credits for signing up")

2. Users spend credits on operations you define:
   - "Sending an email costs 1 credit"
   - "Processing an image costs 10 credits + 0.5 credits per MB"

That's it! Let's see how to set it up.

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

Add to your user model:
```ruby
class User < ApplicationRecord
  has_credits
end
```

That's it! Your app now has a usage credits system. Let's see how to use it:

## Define credit costs

In your `config/initializers/usage_credits.rb`:

```ruby
# Simple fixed cost
operation :send_email do
  cost 1.credit
end

# Cost based on size
operation :process_image do
  cost 10.credits + 0.5.credits_per(:mb)
  validate ->(params) { params[:size] <= 100.megabytes }, "File too large"
end

# With custom validation
operation :generate_ai_response do
  cost 5.credits
  validate ->(params) { params[:prompt].length <= 1000 }, "Prompt too long"
end

# With metadata for better tracking
operation :analyze_data do
  cost 20.credits
  meta category: :analytics, description: "Deep data analysis"
end
```

## Use credits in your code

```ruby
# Check if user has enough credits
if user.has_enough_credits_to?(:process_image, size: 5.megabytes)
  # Spend credits and do the operation
  user.spend_credits_on(:process_image, size: 5.megabytes)
  process_image(params)
else
  redirect_to credits_path, alert: "Not enough credits!"
end

# Check balance
user.credits  # => 1000

# Give bonus credits
user.give_credits(100, reason: "signup_bonus")
```

## Sell credit packs

Define packs users can buy:

```ruby
credit_pack :starter do
  includes 1000.credits
  bonus 100.credits    # Optional bonus credits
  costs 49.dollars
end

# Create a Stripe Checkout session for purchase
pack = UsageCredits.packs[:starter]
session = pack.create_checkout_session(current_user)
redirect_to session.url
```

The gem automatically handles Stripe webhooks to credit the user's wallet after purchase.

## Subscription plans with credits

Give credits with subscriptions:

```ruby
subscription_plan :pro do
  gives 10_000.credits.per_month
  signup_bonus 1_000.credits
  trial_includes 500.credits
  unused_credits :rollover  # Credits roll over to next month
end
```

When a user subscribes to a plan (via the `pay` gem), they'll automatically receive their credits.

## Transaction History & Audit Trail

Every credit transaction is automatically tracked with detailed metadata:

```ruby
# Get recent activity
user.credit_history.recent

# Filter by type
user.credit_history.by_category(:operation_charge)
user.credit_history.by_category(:subscription_monthly)

# Audit operation usage
wallet.transactions
  .where(category: :operation_charge)
  .where("metadata->>'name' = ?", 'process_image')
  .where(created_at: 1.month.ago..)
```

Each operation charge includes detailed audit metadata:
```ruby
{
  name: "process_image",                   # Operation name
  cost: 15,                                # Actual cost charged
  cost_calculator_source: "config/initializers/usage_credits.rb:25", # Where defined
  metadata: { category: "image" },         # Custom metadata
  executed_at: "2024-01-19T16:57:16Z",     # When executed
  params: { size: 1024 },                  # Parameters used
  version: "1.0.0"                         # Gem version
}
```

This makes it easy to:
- Track historical costs
- Audit operation usage
- Generate detailed invoices
- Monitor usage patterns

## Low balance alerts

Get notified when users are running low on credits:

```ruby
UsageCredits.configure do |config|
  # Alert when balance drops below 100 credits
  config.low_balance_threshold = 100.credits
  
  # Handle alerts your way
  config.on_low_balance do |user|
    UserMailer.low_credits_alert(user).deliver_later
  end
end
```

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
0.5.credits_per(:mb)  # => 0.5 credits per megabyte
100.megabytes        # => 100 MB (uses Rails' numeric extensions)
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

### Credit expiration

```ruby
# Credits expire after inactivity
UsageCredits.configure do |config|
  config.expire_credits_after 1.year
end

# Or per subscription
subscription_plan :basic do
  gives 1000.credits.per_month
  expire_after 30.days.of_cancellation
end
```

### Rounding strategy

Configure how credit costs are rounded:

```ruby
UsageCredits.configure do |config|
  config.rounding_strategy = :floor  # Options: :round, :floor, :ceil
end
```

## Testing

Testing is a breeze with our test helpers:

```ruby
# spec/rails_helper.rb
RSpec.configure do |config|
  config.include UsageCredits::TestHelpers
end

# In your tests
RSpec.describe "Image Processing" do
  it "charges correct credits" do
    user = create(:user)
    give_test_credits(user, 1000)
    
    expect {
      user.spend_credits_on(:process_image, size: 5.megabytes)
    }.to change { user.credits }.by(-35)
  end
end
```

## Development

After checking out the repo, run `bin/setup` to install dependencies. Then, run `rake spec` to run the tests. You can also run `bin/console` for an interactive prompt that will allow you to experiment.

To install this gem onto your local machine, run `bundle exec rake install`.

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/rameerez/
usage_credits. Our code of conduct is: just be nice and make your mom proud of what 
you do and post online.

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).
