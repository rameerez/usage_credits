<!-- START doctoc generated TOC please keep comment here to allow auto update -->
<!-- DON'T EDIT THIS SECTION, INSTEAD RE-RUN doctoc TO UPDATE -->

- [1 Installation](#1-installation)
  - [Installing Pay](#installing-pay)
    - [Gemfile](#gemfile)
    - [Migrations](#migrations)
    - [Models](#models)
    - [Next](#next)
- [2 Configuration](#2-configuration)
  - [Configuring Pay](#configuring-pay)
    - [Credentials](#credentials)
    - [Generators](#generators)
    - [Emails](#emails)
    - [Configuration](#configuration)
    - [Background jobs](#background-jobs)
    - [Next](#next-1)
- [3 Customers](#3-customers)
  - [Customers](#customers)
    - [Setting the Payment Processor](#setting-the-payment-processor)
    - [Payment Processor Associations](#payment-processor-associations)
    - [Retrieving a Customer object from the Payment Processor](#retrieving-a-customer-object-from-the-payment-processor)
    - [Next](#next-2)
- [4 Payment Methods](#4-payment-methods)
  - [Payment Methods](#payment-methods)
    - [Updating the default Payment Method](#updating-the-default-payment-method)
    - [Adding other Payment Methods](#adding-other-payment-methods)
    - [Importing Payment Methods](#importing-payment-methods)
    - [Next](#next-3)
- [5 Charges](#5-charges)
  - [Charges](#charges)
    - [Creating a Charge](#creating-a-charge)
    - [Retrieving Charges](#retrieving-charges)
    - [Refunding A Charge](#refunding-a-charge)
    - [Payment Method](#payment-method)
    - [Receipt URL](#receipt-url)
    - [Paddle Receipts](#paddle-receipts)
    - [Next](#next-4)
- [6 Subscriptions](#6-subscriptions)
  - [Subscriptions](#subscriptions)
    - [Creating a Subscription](#creating-a-subscription)
    - [Retrieving a Subscription from the Database](#retrieving-a-subscription-from-the-database)
    - [Subscription Trials](#subscription-trials)
    - [Checking Customer Subscribed Status](#checking-customer-subscribed-status)
    - [Checking Customer Trial Status](#checking-customer-trial-status)
    - [Checking Customer Trial Or Subscribed Status](#checking-customer-trial-or-subscribed-status)
    - [Subscription API](#subscription-api)
    - [Paused Subscriptions](#paused-subscriptions)
    - [Manually syncing subscriptions](#manually-syncing-subscriptions)
    - [Next](#next-5)
- [7 Webhooks](#7-webhooks)
  - [Routes & Webhooks](#routes--webhooks)
    - [Stripe SCA Confirm Page](#stripe-sca-confirm-page)
    - [Webhooks](#webhooks)
    - [Custom Webhook Listeners](#custom-webhook-listeners)
    - [Stripe CLI](#stripe-cli)
    - [Next](#next-6)
- [8 Customizing Models](#8-customizing-models)
  - [Customizing Pay Models](#customizing-pay-models)
    - [Next](#next-7)
- [9 Testing](#9-testing)
  - [Testing Pay](#testing-pay)
- [Braintree](#braintree)
  - [1 Overview](#1-overview)
    - [Using Pay with Braintree](#using-pay-with-braintree)
  - [2 Webhooks](#2-webhooks)
    - [Braintree Webhooks](#braintree-webhooks)
- [Contributing](#contributing)
  - [Adding A Payment Processor](#adding-a-payment-processor)
    - [Adding a Payment Processor to Pay](#adding-a-payment-processor-to-pay)
- [Fake Processor](#fake-processor)
  - [1 Overview](#1-overview-1)
    - [Fake Payment Processor](#fake-payment-processor)
- [Lemon Squeezy](#lemon-squeezy)
  - [1 Overview](#1-overview-2)
    - [Using Pay with Lemon Squeezy](#using-pay-with-lemon-squeezy)
  - [2 Javascript](#2-javascript)
    - [Lemon Squeezy Javascript](#lemon-squeezy-javascript)
  - [3 Webhooks](#3-webhooks)
    - [Lemon Squeezy Webhooks](#lemon-squeezy-webhooks)
- [Marketplaces](#marketplaces)
  - [Braintree](#braintree-1)
    - [Braintree Marketplace Payments](#braintree-marketplace-payments)
  - [Stripe Connect](#stripe-connect)
    - [Stripe Connect](#stripe-connect-1)
- [Paddle Billing](#paddle-billing)
  - [1 Overview](#1-overview-3)
    - [Using Pay with Paddle Billing](#using-pay-with-paddle-billing)
  - [2 Javascript](#2-javascript-1)
    - [Paddle Javascript](#paddle-javascript)
  - [3 Webhooks](#3-webhooks-1)
    - [Paddle Billing Webhooks](#paddle-billing-webhooks)
- [Paddle Classic](#paddle-classic)
  - [1 Overview](#1-overview-4)
    - [Using Pay with Paddle Classic](#using-pay-with-paddle-classic)
  - [2 Javascript](#2-javascript-2)
    - [Paddle Classic Javascript](#paddle-classic-javascript)
  - [3 Webhooks](#3-webhooks-2)
    - [Paddle Classic Webhooks](#paddle-classic-webhooks)
- [Stripe](#stripe)
  - [1 Overview](#1-overview-5)
    - [Using Pay with Stripe](#using-pay-with-stripe)
  - [2 Credentials](#2-credentials)
    - [Stripe Credentials](#stripe-credentials)
  - [3 Javascript](#3-javascript)
    - [Stripe JavaScript](#stripe-javascript)
  - [4 Sca](#4-sca)
    - [Stripe Strong Customer Authentication (SCA)](#stripe-strong-customer-authentication-sca)
  - [5 Webhooks](#5-webhooks)
    - [Stripe Webhooks](#stripe-webhooks)
  - [6 Metered Billing](#6-metered-billing)
    - [Stripe Metered Billing](#stripe-metered-billing)
  - [7 Stripe Tax](#7-stripe-tax)
    - [Stripe Tax](#stripe-tax)
  - [8 Stripe Checkout](#8-stripe-checkout)
    - [Stripe Checkout](#stripe-checkout)
  - [9 Customer Reconciliation](#9-customer-reconciliation)
    - [Stripe customer reconciliation](#stripe-customer-reconciliation)

<!-- END doctoc generated TOC please keep comment here to allow auto update -->

# 1 Installation

## Installing Pay

Pay's installation is pretty straightforward. We'll add the gems, add some migrations, and update our models.

### Gemfile

Add these lines to your application's Gemfile:

```ruby
gem "pay", "~> 8.0"

## To use Stripe, also include:
gem "stripe", "~> 13.0"

## To use Braintree + PayPal, also include:
gem "braintree", "~> 4.7"

## To use Paddle Billing or Paddle Classic, also include:
gem "paddle", "~> 2.5"

## To use Lemon Squeezy, also include:
gem "lemonsqueezy", "~> 1.0"

## To use Receipts gem for creating invoice and receipt PDFs, also include:
gem "receipts", "~> 2.0"
```

And then execute:

```bash
bundle
```

### Migrations

Copy the Pay migrations to your app:

````bash
bin/rails pay:install:migrations
````

Then run the migrations:

```bash
bin/rails db:migrate
```

Make sure you've configured your ActionMailer `default_url_options` so Pay can generate links (for features like Stripe Checkout).

```ruby
## config/application.rb
config.action_mailer.default_url_options = { host: "example.com" }
```

### Models

To add Pay to a model in your Rails app, simply add `pay_customer` to the model:

```ruby
## == Schema Information
##
## Table name: users
##
##  id                     :bigint           not null, primary key
##  email                  :string           default(""), not null

class User < ApplicationRecord
  pay_customer
end
```

**Note:** Pay requires your model to have an `email` attribute. Email is a field that is required by Stripe, Braintree, etc to create a Customer record.

For pay to also send the customer's name to your payment processor, your model should respond to one of the following methods.

* `name`
* `first_name` _and_ `last_name`
* `pay_customer_name`

Name _will not_ sync automatically. See the section below _Syncing attributes_.

#### Customer Attributes

Stripe allows you to send over a hash of attributes to store in the Customer record in addition to email and name.
For more information about the different attributes Stripe accepts for a customer visit the Stripe API documentation [here](https://stripe.com/docs/api/customers/object).

```ruby
class User < ApplicationRecord
  pay_customer stripe_attributes: :stripe_attributes
  # Or using a lambda:
  # pay_customer stripe_attributes: ->(pay_customer) { { metadata: { user_id: pay_customer.owner_id } } }

  def stripe_attributes(pay_customer)
    {
      address: {
        city: pay_customer.owner.city,
        country: pay_customer.owner.country
      },
      metadata: {
        pay_customer_id: pay_customer.id,
        user_id: id # or pay_customer.owner_id
      }
    }
  end
```

Pay will include attributes when creating a Customer and update them when the Customer is updated.

#### Syncing attributes

By adding `pay_customer` to your model, the `Pay::Billable::SyncCustomer` concern will be included. It's responsible for syncing your customer's data from your application to the payment processor in an `after_commit` callback if the method `pay_should_sync_customer?` returns `true`.

By default, `pay_should_sync_customer?` will respond with `saved_change_to_email?`, which means Pay will automatically sync your customer with your payment processor when its e-mail changes.

If you want to automatically sync whenever any other attribute changes, override `pay_should_sync_customer?` in your model. For instance, if you want to sync when your model's name changes, or you are using `stripe_attributes` above to send Stripe the customer's address, it might be a good idea to also sync when these attributes change:

```rb
class User < ApplicationRecord

  def pay_should_sync_customer?
    # super will invoke Pay's default (e-mail changed)
    super || self.saved_change_to_address? || self.saved_change_to_name?
  end

end
```

[ActiveRecord Dirty](https://api.rubyonrails.org/classes/ActiveRecord/AttributeMethods/Dirty.html) is your friend here.

### Next

See [Configuration](#2-configuration)

# 2 Configuration

## Configuring Pay

Pay comes with a lot of configuration out of the box for you, but you'll need to add your API tokens for your payment provider.

### Credentials

Pay automatically looks up credentials for each payment provider. We recommend storing them in the Rails credentials.

###### Rails Credentials

You'll need to add your API keys to your Rails credentials. You can do this by running:

```bash
rails credentials:edit --environment=development
```

They should be formatted like the following:

```yaml
stripe:
  private_key: xxxx
  public_key: yyyy
  webhook_receive_test_events: true
  signing_secret:
  - aaaa
  - bbbb
braintree:
  private_key: xxxx
  public_key: yyyy
  merchant_id: aaaa
  environment: sandbox
paddle_billing:
  client_token: aaaa
  api_key: yyyy
  signing_secret: pdl_ntfset...
  environment: sandbox
paddle_classic:
  vendor_id: xxxx
  vendor_auth_code: yyyy
  public_key_base64: MII...==
  environment: sandbox
lemon_squeezy:
  api_key: xxxx
  store_id: yyyy
  signing_secret: aaaa
```

You can also nest these credentials under the Rails environment if using a shared credentials file.

```yaml
development:
  stripe:
    private_key: xxxx
## ...
```

###### Environment Variables

Pay will also check environment variables for API keys:

* `STRIPE_PUBLIC_KEY`
* `STRIPE_PRIVATE_KEY`
* `STRIPE_SIGNING_SECRET`
* `STRIPE_WEBHOOK_RECEIVE_TEST_EVENTS`
* `BRAINTREE_MERCHANT_ID`
* `BRAINTREE_PUBLIC_KEY`
* `BRAINTREE_PRIVATE_KEY`
* `BRAINTREE_ENVIRONMENT`
* `PADDLE_BILLING_API_KEY`
* `PADDLE_BILLING_CLIENT_TOKEN`
* `PADDLE_BILLING_SIGNING_SECRET`
* `PADDLE_BILLING_ENVIRONMENT`
* `PADDLE_CLASSIC_VENDOR_ID`
* `PADDLE_CLASSIC_VENDOR_AUTH_CODE`
* `PADDLE_CLASSIC_PUBLIC_KEY`
* `PADDLE_CLASSIC_PUBLIC_KEY_FILE`
* `PADDLE_CLASSIC_PUBLIC_KEY_BASE64`
* `PADDLE_CLASSIC_ENVIRONMENT`
* `LEMON_SQUEEZY_API_KEY`
* `LEMON_SQUEEZY_STORE_ID`
* `LEMON_SQUEEZY_SIGNING_SECRET`

> [!TIP]
>
> Are you using any of these payment processors for the very first time? Take a look at their respective configuration doc for generating these keys:
>
> - [Stripe](/docs/stripe/2_credentials.md)
> - [Paddle Billing](#configuration)
> - [Paddle Classic](#paddle-public-key)

##### STRIPE_WEBHOOK_RECEIVE_TEST_EVENTS (Default to TRUE)
As per the guidance from https://support.stripe.com/questions/connect-account-webhook-configurations: "When a connected account is linked solely in live mode to your platform, both live and test events are sent to your live Connect Webhook Endpoint." Therefore, you can set this to false if you wish to receive only live events in Production.

### Generators

If you want to modify the Stripe SCA template or any other views, you can copy over the view files using:

```bash
bin/rails generate pay:views
```

If you want to modify the email templates, you can copy over the view files using:

```bash
bin/rails generate pay:email_views
```

### Emails

Emails can be enabled/disabled as a whole by using the `send_emails` configuration option or independently by
using the `emails` configuration option as shown in the configuration section below (all emails are enabled by default).

When enabled, the following emails will be sent when:

- A payment action is required
- A payment failed
- A charge succeeded
- A charge was refunded
- A yearly subscription is about to renew
- A subscription trial is about to end
- A subscription trial has ended

### Configuration

Need to make some changes to how Pay is used? You can create an initializer `config/initializers/pay.rb`

```ruby
Pay.setup do |config|
  # For use in the receipt/refund/renewal mailers
  config.business_name = "Business Name"
  config.business_address = "1600 Pennsylvania Avenue NW"
  config.application_name = "My App"
  config.support_email = "Business Name <support@example.com>"

  config.default_product_name = "default"
  config.default_plan_name = "default"

  config.automount_routes = true
  config.routes_path = "/pay" # Only when automount_routes is true
  # All processors are enabled by default. If a processor is already implemented in your application, you can omit it from this list and the processor will not be set up through the Pay gem.
  config.enabled_processors = [:stripe, :braintree, :paddle_billing, :paddle_classic, :lemon_squeezy]

  # To disable all emails, set the following configuration option to false:
  config.send_emails = true

  # All emails can be configured independently as to whether to be sent or not. The values can be set to true, false or a custom lambda to set up more involved logic. The Pay defaults are show below and can be modified as needed.
  config.emails.payment_action_required = true
  config.emails.payment_failed = true
  config.emails.receipt = true
  config.emails.refund = true
  # This example for subscription_renewing only applies to Stripe, therefore we supply the second argument of price
  config.emails.subscription_renewing = ->(pay_subscription, price) {
    (price&.type == "recurring") && (price.recurring&.interval == "year")
  }
  config.emails.subscription_trial_will_end = true
  config.emails.subscription_trial_ended = true

  # Customize who receives emails. Useful when adding additional recipients other than the Pay::Customer. This defaults to the pay customer's email address.
  # config.mail_to = ->(mailer, params) { "#{params[:pay_customer].customer_name} <#{params[:pay_customer].email}>" }

  # Customize mail() arguments. By default, only includes { to: }. Useful when you want to add cc, bcc, customize the mail subject, etc.
  # config.mail_arguments = ->(mailer, params) {
  #   {
  #     to: Pay.mail_recipients.call(mailer, params)
  #   }
  # }
end
```

### Background jobs

If a user's email is updated, Pay will enqueue a background job (`CustomerSyncJob`) to sync the email with the payment processors they have setup.

It is important you set a queue_adapter for this to happen. If you don't, the code will be executed immediately upon user update. [More information here](https://guides.rubyonrails.org/v6.1/active_job_basics.html#backends)

```ruby
## config/application.rb
config.active_job.queue_adapter = :sidekiq
```

### Next

See [Customers](#3-customers)

# 3 Customers

## Customers

Every payment processor has a Customer object that keeps track of your customers by email. Pay keeps track of these Customers with the `Pay::Customer` model.

### Setting the Payment Processor

Before you can process payments, you need to assign a payment processor for the user.

```ruby
@user.set_payment_processor :stripe
@user.set_payment_processor :braintree
@user.set_payment_processor :paddle_billing
@user.set_payment_processor :paddle_classic
@user.set_payment_processor :lemon_squeezy
@user.set_payment_processor :fake_processor, allow_fake: true
```

This creates a `Pay::Customer` record in the database that keeps track of the payment processor's ID and allows you to interact with the API to charge and subscribe this customer.

The `fake_processor` is restricted by default so users can't give themselves free access to your application.

Alternatively, you can set a default processor for all users.

```ruby
class User < ApplicationRecord
  pay_customer default_payment_processor: :stripe
end
```

### Payment Processor Associations

After setting the payment processor, your model will have a `payment_processor` they can use to create charges, subscriptions, etc.

```ruby
@user.payment_processor
##=> #<Pay::Customer processor: "stripe", processor_id: "cus_1000">
```

This record keeps track of payment processor that is active and the ID for the customer on the API. It also is associated with all Charges, Subscriptions, and Payment Methods.

A user might switch between payment processors. For example, they might initially subscribe using Braintree, cancel after a while, and resubscribe using Stripe later on.

Pay keeps track of these with a `has_many :pay_customers` association.

```ruby
@user.pay_customers
##=> [#<Pay::Customer>, #<Pay::Customer>]
```

Only one `Pay::Customer` can be the default which is used for `payment_processor`.

### Retrieving a Customer object from the Payment Processor

For Paddle Billing and Lemon Squeezy, using the `api_record` method will create a new customer on the payment processor.

If the `processor_id` is already set, it will retrieve the customer from the payment processor and return the object
directly from the API. Like so:

```ruby
@user.payment_processor.api_record
##=> #<Stripe::Customer>
##=> #<Paddle::Customer>
##=> #<LemonSqueezy::Customer>
```

###### Paddle Classic:

It is currently not possible to retrieve a Customer object through the Paddle Classic API.

### Next

See [Payment Methods](#4-payment-methods)

# 4 Payment Methods

## Payment Methods

The first thing you'll need to do is add a payment method. You will get a payment method token from the payment processor's Javascript library. See the payment processors docs for how to setup their Javascript.

### Updating the default Payment Method

To update the default payment method on file, you can use `update_payment_method`:

```ruby
@user.payment_processor.update_payment_method(params[:payment_method_token])
```

This will add the payment method via the API and mark it as the default for future payments.

###### Paddle Billing

For updating payment method details on Paddle, a transaction ID is required. This can be generated by using:

```ruby
subscription = @user.payment_processor.subscription(name: "plan name")
transaction  = subscription.payment_method_transaction
```

Once you have a transaction ID, you can then pass that through to Paddle.js like so

```html
<a href="#"
  class="paddle_button"
  data-display-mode="overlay"
  data-theme="light"
  data-locale="en"
  data-transaction-id="<%= transaction.id %>"
>
	Update Payment Details
</a>
```

This will then open the Paddle overlay and allow the user to update their payment details.

For more information, [see the Paddle documentation](https://developer.paddle.com/build/subscriptions/update-payment-details)

###### Paddle Classic

Paddle uses an [Update Payment Details URL](https://developer.paddle.com/guides/how-tos/subscriptions/update-payment-details) for each customer which allows them to update the payment method. This is stored on the `Pay::Subscription` record for easy access.

```ruby
@user.payment_processor.subscription.paddle_update_url
```

You may either redirect to this URL or use Paddle's Javascript to render as an overlay or inline.

###### Lemon Squeezy

Much like Paddle, Lemon Squeezy uses an Update Payment Details URL for each customer which allows them to update
the payment method. This URL expires after 24 hours, so this method retrieves a new one from the API each time.

```ruby
@user.payment_processor.subscription.update_url
```

Lemon Squeezy also offer a [Customer Portal](https://www.lemonsqueezy.com/features/customer-portal) where customers
can manage their subscriptions and payment methods. You can link to this portal using the `portal_url` method.
Just like the Update URL, this URL expires after 24 hours, so this method retrieves a new one from the API each time.

```ruby
@user.payment_processor.subscription.portal_url
```

You may either redirect to this URL or use Paddle's Javascript to render as an overlay or inline.

### Adding other Payment Methods

You can also add a payment method without making it the default.

```ruby
@user.payment_processor.add_payment_method(params[:payment_method_token], default: false)
```

### Importing Payment Methods

#### Paddle Billing

If a Paymment Method doesn't exist in Pay, then you can use the following method to create it from Paddle Billing:

It takes a `Pay::Customer` and a Paddle Transaction ID as arguments.

```ruby
Pay::PaddleBilling::PaymentMethod.sync_from_transaction pay_customer: @user.payment_processor, transaction: "txn_abc123"
```

If a Payment Method already exists with the token, then it will be updated with the latest details from Paddle.

### Next

See [Charges](#5-charges)


# 5 Charges

## Charges

Pay allows you to make one-time charges to a customer.

### Creating a Charge

To charge a customer, you need to assign a payment method token before you can charge them.

```ruby
@user.payment_processor.payment_method_token = params[:payment_method_token]
@user.payment_processor.charge(15_00) # $15.00 USD
```

The `charge` method takes the amount in cents as the primary argument.

You may pass optional arguments that will be directly passed on to the payment processor. For example, you can use these options to charge different currencies:

```ruby
@user.payment_processor.charge(15_00, currency: "cad")
```

On failure, a `Pay::Error` will be raised with details about the payment failure.

###### Paddle Classic Charges

When creating charges with Paddle, they need to be approved by the customer. This is done by
passing the Paddle Transaction ID to a Paddle.js checkout.

To see the required fields, see the [Paddle API docs](https://developer.paddle.com/api-reference/transactions/create-transaction).

The amount can be set to 0 as this will be set by the Price set on Paddle, so will be ignored.

```ruby
@user.payment_processor.charge(0, {
  items: [
    {
      quantity: 1,
      price_id: "pri_abc123"
    }
  ],
  # include additional fields here
})
```

Then you can set the `transactionId` attribute for Paddle.js. For more info, see the [Paddle.js docs](https://developer.paddle.com/paddlejs/methods/paddle-checkout-open)

###### Paddle Classic Charges

Paddle Classic requires an active subscription on the customer in order to create a one-time charge. It also requires a `charge_name` for the charge.

```ruby
@user.payment_processor.charge(1500, {charge_name: "Test"}) # $15.00 USD
```

###### Lemon Squeezy Charges

Lemon Squeezy currently doesn't support one-time charges.

### Retrieving Charges

To see a list of charges for a customer, you can access them with:

```ruby
@user.payment_processor.charges
```

### Refunding A Charge

You can refund a charge by calling `refund!` on the charge:

```ruby
charge = @user.payment_processor.charges.last

## Refund the full amount
charge.refund!

## Partial refund of $5.00
charge.refund!(5_00)
```

### Payment Method

Charges record a copy of their payment method. This allows users to update their payment methods without losing the information on previous purchases.

The details saved will vary depending upon the payment method used.

```ruby
@charge.payment_method_type
##=> card, paypal, sepa, ideal, etc

@charge.brand
##=> Visa, Discover, MasterCard, American Express, PayPal, Venmo, etc

@charge.last4 #=> 4242
@charge.exp_month #=> 12
@charge.exp_year #=> 2021
@charge.email #=> PayPal email
@charge.username #=> Venmo username
@charge.bank #=> Bank name
```

### Receipt URL

Paddle Classic and Stripe provide a receipt URL for each payment.

```ruby
@charge.paddle_receipt_url
@charge.stripe_receipt_url
```

### Paddle Receipts

Paddle Billing doesn't provide a receipt URL like Paddle Classic did.

In order to retrieve a PDF invoice for a transaction, an API request is required. This will return a URL to the PDF invoice. This URL is not permanent and will expire after a short period of time.

```ruby
Paddle::Transaction.invoice(id: @charge.processor_id)
```

### Next

See [Subscriptions](#6-subscriptions)

# 6 Subscriptions

## Subscriptions

Subscriptions are handled differently by each payment processor. Pay does its best to treat them the same.

Pay stores subscriptions in the `Pay::Subscription` model. Each subscription has a `name` that you can use to handle multiple subscriptions per customer.

### Creating a Subscription

To subscribe a user, you can call the `subscribe` method.

```ruby
@user.payment_processor.subscribe(name: "default", plan: "monthly")
```

You can pass additional options to go directly to the payment processor's API. For example, the `quantity` option to subscribe to a plan with per-seat pricing.

```ruby
@user.payment_processor.subscribe(name: "default", plan: "monthly", quantity: 3)
```

Subscribe takes several arguments and options:

* `name` - A name for the subscription that's used internally. This allows a customer to have multiple subscriptions. Defaults to `"default"`
* `plan` - The Plan or Price ID to subscribe to. Defaults to `"default"`
* `quantity` - The quantity of the subscription. Defaults to `1`
* `trial_period_days` - Number of days for the subscription's trial.
* Other options may be passed and will be sent directly to the payment processor's API.

###### Paddle Classic Subscriptions

Paddle does not allow you to create a subscription through the API.

Instead, Pay uses webhooks to create the the subscription in the database. The Paddle [passthrough parameter](https://developer.paddle.com/guides/how-tos/checkout/pass-parameters) is required during checkout to associate the subscription with the correct `Pay::Customer`.

In your Javascript, include `passthrough` in Checkout using the `Pay::PaddleClassic.passthrough` helper.

```javascript
Paddle.Checkout.open({
  product: 12345,
  passthrough: "<%= Pay::PaddleClassic.passthrough(owner: current_user) %>"
});
```

Or with Paddle Button Checkout:

```html
<a href="#!" class="paddle_button" data-product="12345" data-email="<%= current_user.email %>" data-passthrough="<%= Pay::PaddleClassic.passthrough(owner: current_user) %>">Buy now!</a>
```

####### Paddle Classic Passthrough Helper

Pay provides a helper method for generating the `passthrough` JSON object to associate the purchase with the correct Rails model.

```ruby
Pay::PaddleClassic.passthrough(owner: current_user, foo: :bar)
##=> { owner_sgid: "xxxxxxxx", foo: "bar" }

## To generate manually without the helper
##=> { owner_sgid: current_user.to_sgid.to_s, foo: "bar" }.to_json
```

> Pay uses a signed GlobalID to ensure that the subscription cannot be tampered with.

When processing Paddle webhooks, Pay parses the `passthrough` JSON string and verifies the `owner_sgid` hash in order to find the correct `Pay::Customer` record.

The passthrough parameter `owner_sgid` is only required for creating a subscription.

###### Paddle Billing Subscriptions

As with Paddle Classic, Paddle Billing does not allow you to create a subscription through the API.

Instead, Pay uses webhooks to create the the subscription in the database. The Paddle `customer` field is required
during checkout to associate the subscription with the correct `Pay::Customer`.

Firstly, retrieve/create a Paddle customer by calling `customer`.

```ruby
@user.payment_processor.customer
```

Then using either the Javascript `Paddle.Checkout.open` method or the Paddle Button Checkout, pass the `customer` object
and an array of items to subscribe to.

```javascript
Paddle.Checkout.open({
  customer: {
    id: "<%= @user.payment_processor.processor_id %>",
  },
  items: [
    {
      // The Price ID of the subscription plan
      priceId: "pri_abc123",
      quantity: 1
    }
  ],
});
```

Or with Paddle Button Checkout:

```html
<a href='#'
  class='paddle_button'
  data-display-mode='overlay'
  data-locale='en'
  data-items='[
    {
      "priceId": "pri_abc123",
      "quantity": 1
    }
  ]'
  data-customer-id="<%= @user.payment_processor.processor_id %>"
>
  Subscribe
</a>
```

###### Lemon Squeezy Subscriptions

Lemon Squeezy does not allow you to create a subscription through the API. Instead, Pay uses webhooks to create the
subscription in the database.

Lemon Squeezy offer 2 checkout flows, a hosted checkout and a checkout overlay. When creating a Product in the
Lemon Squeezy dashboard, clicking the "Share" button will provide you with the URLs for either checkout flow.

For example, the hosted checkout flow:

```html
https://STORE.lemonsqueezy.com/checkout/buy/UUID
```

And the checkout overlay flow:

```html
<a href="https://STORE.lemonsqueezy.com/checkout/buy/UUID?embed=1" class="lemonsqueezy-button">Buy A Product</a>
<script src="https://assets.lemonsqueezy.com/lemon.js" defer></script>
```

It's currently not possible to pass a pre-existing Customer ID to Lemon Squeezy, so you can use the passthrough
method to associate the subscription with the correct `Pay::Customer`.

You can pass additional options to the checkout session. You can view the [supported fields here](https://docs.lemonsqueezy.com/help/checkout/prefilling-checkout-fields)
and the [custom data field here](https://docs.lemonsqueezy.com/help/checkout/passing-custom-data).

####### Lemon Squeezy Passthrough Helper

You can use the `Pay::LemonSqueezy.passthrough` helper to generate the `checkout[custom][passthrough]` field.

You'll need to replace `storename` with your store URL slug & `UUID` with the UUID of the plan you want to use, which
can be found by clicking Share on the product in Lemon Squeezy's dashboard.

```html
<a
  class="lemonsqueezy-button"
  href="https://storename.lemonsqueezy.com/checkout/buy/UUID?checkout[custom][passthrough]=<%= Pay::LemonSqueezy.passthrough(owner: @user) %>">
  Sign up to Plan
</a>
```

### Retrieving a Subscription from the Database

```ruby
@user.payment_processor.subscription(name: "default")
```

### Subscription Trials

There are two types of trials for subscriptions: with or without a payment method upfront.

Stripe is the only payment processor that allows subscriptions without a payment method. Braintree and Paddle require a payment method on file to create a subscription.

###### Trials Without Payment Method

To create a trial without a card, we can use the Fake Processor to create a subscription with matching trial and end times.

```ruby
time = 14.days.from_now
@user.set_payment_processor :fake_processor, allow_fake: true
@user.payment_processor.subscribe(trial_ends_at: time, ends_at: time)
```

This will create a fake subscription in our database that we can use. Once expired, the customer will need to subscribe using a real payment processor.

```ruby
@user.payment_processor.on_generic_trial?
##=> true
```

###### Trials with Payment Method required

Braintree and Paddle require payment methods before creating a subscription.

```ruby
@user.set_payment_processor :braintree
@user.payment_processor.payment_method_token = params[:payment_method_token]
@user.payment_processor.subscribe()
```

### Checking Customer Subscribed Status

```ruby
@user.payment_processor.subscribed?
```

You can also check for a specific subscription or plan:

```ruby
@user.payment_processor.subscribed?(name: "default", processor_plan: "monthly")
```

### Checking Customer Trial Status

You can check if the user is on a trial by simply asking:

```ruby
@user.payment_processor.on_trial?
##=> true or false
```

You can also check if the user is on a trial for a specific subscription name or plan.

```ruby
@user.payment_processor.on_trial?(name: 'default', plan: 'plan')
##=> true or false
```

### Checking Customer Trial Or Subscribed Status

For paid features of your app, you'll often want to check if the user is on trial OR subscribed. You can use this method to check both at once:

```ruby
@user.payment_processor.on_trial_or_subscribed?
```

You can also check for a specific subscription or plan:

```ruby
@user.payment_processor.on_trial_or_subscribed?(name: "default", processor_plan: "annual")
```

### Subscription API

Individual subscriptions provide similar helper methods to check their state.

##### Checking a Subscription's Trial Status

```ruby
@user.payment_processor.subscription.on_trial? #=> true or false
```

##### Checking a Subscription's Cancellation Status

```ruby
@user.payment_processor.subscription.cancelled? #=> true or false
```

##### Checking if a Subscription is on Grace Period

```ruby
@user.payment_processor.subscription.on_grace_period? #=> true or false
```

##### Checking if a Subscription is Active

```ruby
@user.payment_processor.subscription.active? #=> true or false
```

##### Cancel a Subscription (At End of Billing Cycle)

```ruby
@user.payment_processor.subscription.cancel
```

###### Paddle

In addition to the API, Paddle provides a subscription [Cancel URL](https://developer.paddle.com/guides/how-tos/subscriptions/cancel-and-pause) that you can redirect customers to cancel their subscription.

```ruby
@user.payment_processor.subscription.paddle_cancel_url
```

##### Cancel a Subscription Immediately

```ruby
@user.payment_processor.subscription.cancel_now!
```

The subscription will be canceled immediately and you *cannot* resume the subscription.

If you wish to refund your customer for the remaining time, you will need to calculate that and issue a refund separately.

##### Swap a Subscription to another Plan

If a user wishes to change subscription plans, you can pass in the Plan or Price ID into the `swap` method:

```ruby
@user.payment_processor.subscription.swap("yearly")
```

Braintree does not allow this via their API, so we cancel and create a new subscription for you (including proration discount).

##### Resume a Subscription

A user may wish to resume their canceled subscription during the grace period. You can resume a subscription with:

```ruby
@user.payment_processor.subscription.resume
```

##### Retrieving the raw Subscription object from the Processor

```ruby
@user.payment_processor.subscription.processor_subscription
##=> #<Stripe::Subscription>
```

### Paused Subscriptions

Stripe and Paddle allow you to pause subscriptions. These subscriptions are considered to be active. This allows the subscriptions
to be displayed to your users so they can resume the subscription when ready. You will need to check if the subscription is
paused if you wish to limit any feature access within your application.

##### Checking if a Subscription is Paused

```ruby
@user.payment_processor.subscription.paused? #=> true or false
```

##### Pause a Subscription (Stripe and Paddle only)

###### Pause a Stripe Subscription

Stripe subscriptions have several behaviors.
* `behavior: void` will put the subscription on a grace period until the end of the current period.
* `behavior: keep_as_draft` will pause the subscription invoices but the subscription is still active. Use this to delay payments until later.
* `behavior: mark_uncollectible` will pause the subscription invoices but the subscription is still active. Use this to provide free access temporarily.

Calling pause with no arguments will set `behavior: "mark_uncollectible"` by default.

```ruby
@user.payment_processor.subscription.pause
```

You can set this to another option as shown below.
```ruby
@user.payment_processor.subscription.pause(behavior: "mark_uncollectible")
@user.payment_processor.subscription.pause(behavior: "keep_as_draft")
@user.payment_processor.subscription.pause(behavior: "void")
@user.payment_processor.subscription.pause(behavior: "mark_uncollectible", resumes_at: 1.month.from_now)
```

###### Pause a Paddle Classic Subscription

Paddle will pause payments at the end of the period. The status remains `active` until the period ends with a `paused_from` value to denote when the subscription pause will take effect. When the status becomes `paused` the subscription is no longer active.

```ruby
@user.payment_processor.subscription.pause
```

##### Resuming a Paused Subscription

```ruby
@user.payment_processor.subscription.resume
```

### Manually syncing subscriptions

In general, you don't need to use these methods as Pay's webhooks will keep you all your subscriptions in sync automatically.

However, for instance, a user returning from Stripe Checkout / Stripe Billing Portal might still see stale subscription information before the Webhook is processed, so these might come in handy.

#### Individual subscription

```rb
@user.payment_processor.subscription.sync!
```

#### All at once

There's a convenience method for syncing all subscriptions at once (currently Stripe only).

```rb
@user.payment_processor.sync_subscriptions
```

As per Stripe's docs [here](https://stripe.com/docs/api/subscriptions/list?lang=ruby), by default the list of subscriptions **will not included canceled ones**. You can, however, retrieve them like this:

```rb
@user.payment_processor.sync_subscriptions(status: "all")
```

Since subscriptions views are not frequently accessed by users, you might accept to trade off some latency for increased safety on these views, avoiding showing stale data. For instance, in your controller:

```rb
class SubscriptionsController < ApplicationController

  def show
    # This guarantees your user will always see up-to-date subscription info
    # when returning from Stripe Checkout / Billing Portal, regardless of
    # webhooks race conditions.
    current_user.payment_processor.sync_subscriptions(status: "all")
  end

  def create
    # Let's say your business model doesn't allow multiple subscriptions per
    # user, and you want to make extra sure they are not already subscribed before showing the new subscription form.
    current_user.payment_processor.sync_subscriptions(status: "all")

    redirect_to subscription_path and return if current_user.payment_processor.subscription.active?
  end
```

### Next

See [Webhooks](#7-webhooks)

# 7 Webhooks

## Routes & Webhooks

Routes are automatically mounted to `/pay` by default.

### Stripe SCA Confirm Page

We provide a route for confirming Stripe SCA payments at `/pay/payments/:payment_intent_id`

See [Stripe SCA docs](#4-sca)

### Webhooks

Pay comes with a bunch of different webhook handlers built-in. Each payment processor has different requirements for handling webhooks and we've implemented all the basic ones for you.

#### Routes

Webhooks are automatically mounted at `/pay/webhooks/:provider`

To configure webhooks on your payment processor, use the following URLs while replacing `example.org` with your own domain:

* **Stripe** - `https://example.org/pay/webhooks/stripe`
* **Braintree** - `https://example.org/pay/webhooks/braintree`
* **Paddle Billing** - `https://example.org/pay/webhooks/paddle_billing`
* **Paddle Classic** - `https://example.org/pay/webhooks/paddle_classic`
* **Lemon Squeezy** - `https://example.org/pay/webhooks/lemon_squeezy`

##### Mount path

If you have a catch all route (for 404s, etc) and need to control where/when the webhook endpoints mount, you will need to disable automatic mounting and mount the engine above your catch all route.

```ruby
## config/initializers/pay.rb
config.automount_routes = false
```

```ruby
## config/routes.rb
mount Pay::Engine, at: '/other-path'
```

If you just want to modify where the engine mounts it's routes then you can change the path.

```ruby
## config/initializers/pay.rb
config.routes_path = '/other-path'
```

#### Event Naming

Since we support multiple payment providers, each event type is prefixed with the payment provider:

```ruby
"stripe.charge.succeeded"
"braintree.subscription_charged_successfully"
"paddle_billing.subscription.created"
"paddle_classic.subscription_created"
"lemon_squeezy.subscription_created"
```

### Custom Webhook Listeners

To add your own webhook listener, you can simply subscribe to the event type.

```ruby
## app/webhooks/my_charge_succeeded_processor.rb
class MyChargeSucceededProcessor
  def call(event)
    # do your processing here
  end
end

## config/initializers/pay.rb
ActiveSupport.on_load(:pay) do
  Pay::Webhooks.delegator.subscribe "stripe.charge.succeeded", MyChargeSucceededProcessor.new
end
```

If you are sending emails from your custom webhook handlers, be sure to use the [`Pay.send_email?` method](https://github.com/pay-rails/pay/blob/c067771d8c7514acde4b948b474caf054bb0e25d/lib/pay.rb#L113)
in a conditional check to ensure that you don't send any emails if they are disabled either individually or as a whole.
For example:

```ruby
## app/webhooks/my_charge_succeeded_processor.rb
class MyChargeSucceededProcessor
  def call(event)
    pay_charge = Pay::Stripe::Charge.sync(event.data.object.id, stripe_account: event.try(:account))

    if pay_charge && Pay.send_email?(:receipt, pay_charge) # <---- Note the usage of the `send_email?` method here
      Pay.mailer.with(pay_customer: pay_charge.customer, pay_charge: pay_charge).receipt.deliver_later
    end
  end
end
```

#### Unsubscribing from a webhook listener

Need to unsubscribe or disable one of the default webhook processors? Simply unsubscribe from the event name:

```ruby
Pay::Webhooks.delegator.unsubscribe "stripe.charge.succeeded"
```

### Stripe CLI

The Stripe CLI lets you forward webhooks to your local Rails server during development. See the [Stripe Webhooks](#5-webhooks) docs on how to use it.

### Next

See [Customizing Models](#8-customizing-models)

# 8 Customizing Models

## Customizing Pay Models

Want to add functionality to a Pay model? You can define a concern and simply include it in the model when Rails loads the code.

First, you'll need to create a concern with the functionality you'd like to add.

```ruby
## app/models/concerns/charge_extensions.rb
module ChargeExtensions
  extend ActiveSupport::Concern

  included do
    belongs_to :order
    after_create :fulfill_order
  end

  def fulfill_order
    order.fulfill!
  end
end
```

Then you can tell Rails to include the concern whenever it loads the application.

```ruby
## config/initializers/pay.rb

## Re-include the ChargeExtensions every time Rails reloads
Rails.application.config.to_prepare do
  Pay::Charge.include ChargeExtensions
end
```

### Next

See [Testing](#9-testing)

# 9 Testing

## Testing Pay

Pay comes with a fake payment processor to make testing easy. It can also be used in production to give free access to friends, testers, etc.

#### Using the Fake Processor

To protect from abuse, the `allow_fake` option must be set to `true` in order to use the Fake Processor.

```ruby
@user.set_payment_processor :fake_processor, allow_fake: true
```

You can then make charges and subscriptions like normal. These will be generated with random unique IDs just like a real payment processor.

```ruby
pay_charge = @user.payment_processor.charge(19_00)
pay_subscription = @user.payment_processor.subscribe(plan: "fake")
```

#### Test Examples

You'll want to test the various situations like subscriptions on trial, active, canceled on grace period, canceled permanently, etc.

Fake processor charges and subscriptions will automatically assign these fields to the database for easy testing of different situations:

```ruby
## Canceled subscription
@user.payment_processor.subscribe(plan: "fake", ends_at: 1.week.ago)

## On Trial
@user.payment_processor.subscribe(plan: "fake", trial_ends_at: 1.week.from_now)

## Expired Trial
@user.payment_processor.subscribe(plan: "fake", trial_ends_at: 1.week.ago)
```

# Braintree

## 1 Overview

### Using Pay with Braintree

## 2 Webhooks

### Braintree Webhooks

# Contributing

## Adding A Payment Processor

### Adding a Payment Processor to Pay

Each payment processor requires implementation of several things:

* Billable
* PaymentMethods
* Charge
* Subscription
* Webhooks

Pay instantiates Payment Processor classes to implement the API requests to the payment processor.

For example, a `Pay::Charge.refund!` will look up the payment processor (Stripe, for example) and instantiate `Pay::Stripe::Charge` with the `Pay::Charge` record. It will then call `refund!` allowing `Pay::Stripe::Charge` to handle the `refund` API request.

Each payment processor needs to implement the same classes in order to fulfill the hooks for making API requests.

We recommend copying FakeProcessor as the basis for your new payment processor and replacing each method with the appropriate API requests.

#### Webhook Controller

Each payment processer can define it's own controller for processing any required webhooks.

For example, `stripe` has [app/controllers/pay/webhooks/stripe_controller.rb](../../app/controllers/pay/webhooks/stripe_controller.rb)

See also [config/routes.rb](../../config/routes.rb) for defining routes.

The webhook controller is responsible for verifying the webhook payload for authenticity and then sending to the Pay Webhook Delegator

##### Pay Webhook Delegator

The Webhook Delegator is responsible for taking an event type and sending it for processing.

It uses [ActiveSupport::Notifications](https://api.rubyonrails.org/classes/ActiveSupport/Notifications.html) to subscribe and instrument events.

```ruby
Pay::Webhooks.configure do |events|
  events.subscribe "stripe.charge.succeeded", Pay::Stripe::Webhooks::ChargeSucceeded.new
end

module Pay
  module Stripe
    module Webhooks
      class ChargeSucceeded
        def call(event)
          # processing goes here
        end
      end
    end
  end
end
```

For example, when a `stripe.charge.succeeded` event gets processed, the webhook delegator sends the event to any classes that are subscribed to the event type.

Internally, these events are automatically prefaced with the `pay` namespace so they don't conflict with other events. `stripe.charge.succeeded` is internally routed as `pay.stripe.charge.succeeded`. Payment processors should _not_ preface with `pay.` as it is automatically added.

# Fake Processor

## 1 Overview

### Fake Payment Processor

The fake payment processor is useful for:

* Testing
* Free subscriptions & charges for users like your team, friends, etc

#### Usage

Simply assign `processor: :fake_processor, processor_id: rand(1_000_000), pay_fake_processor_allowed: true` to your user.

```ruby
user = User.create!(
  email: "gob@bluth.com",
  processor: :fake_processor,
  processor_id: rand(1_000_000),
  pay_fake_processor_allowed: true
)

user.charge(25_00)
user.subscribe("default")
```

#### Security

You don't want malicious users using the fake processor to give themselves free access to your products.

Pay provides a virtual attribute and validation to ensure the fake processor is only assigned when explicitly allowed.

```ruby
### Inside Pay::Billable
attribute :pay_fake_processor_allowed, :boolean, default: false

validate :pay_fake_processor_is_allowed

def pay_fake_processor_is_allowed
  return unless processor == "fake_processor"
  errors.add(:processor, "must be a valid payment processor") unless pay_fake_processor_allowed?
end
```

`pay_fake_processor_allowed` must be set to `true` before saving. This attribute should *not* included in your permitted_params.

The validation checks if this attribute is enabled and raises a validation error if not. This prevents malicious uses from submitting `user[processor]=fake_processor` in a form.

#### Trials Without Payment Method

To create a trial without a card, we can use the Fake Processor to create a subscription with matching trial and end times.

```ruby
time = 14.days.from_now
@user.set_payment_processor :fake_processor, allow_fake: true
@user.payment_processor.subscribe(trial_ends_at: time, ends_at: time)
```

This will create a fake subscription in our database that we can use. Once expired, the customer will need to subscribe using a real payment processor.

```ruby
@user.payment_processor.on_generic_trial?
###=> true
```

# Lemon Squeezy

## 1 Overview

### Using Pay with Lemon Squeezy

Lemon Squeezy works differently than most of the other payment processors so it comes with some limitations and differences.

* Checkout only happens via iFrame or hosted page
* Cancelling a subscription cannot be resumed

#### Creating Customers

First, you tell Pay which payment processor to use:

```ruby
### Set the payment processor
@user.set_payment_processor :lemon_squeezy
```

Then you can create a [Checkout](https://docs.lemonsqueezy.com/api/checkouts/create-checkout) to let the user purchase a product.

```ruby
@user.payment_processor.checkout(variant_id: "xyz")
```

Customers are lazy created, so they won't be created until you create a Checkout or ask for the Lemon Squeezy customer object through Pay.

```ruby
@user.payment_processor.api_record
```

#### Subscriptions

Lemon Squeezy subscriptions are not created through the API, but through Webhooks. When a
subscription is created, Lemon Squeezy will send a webhook to your application. Pay will
automatically create the subscription for you.

#### Configuration

##### API Key

You can generate an API key [here](https://app.lemonsqueezy.com/settings/api)

##### Store ID

Certain API calls require a Store ID. You can find this [here](https://app.lemonsqueezy.com/settings/stores).

##### Signing Secret

When creating a webhook, you have the option to set a signing secret. This is used to verify
that the webhook request is coming from Lemon Squeezy.

You'll find this page [here](https://app.lemonsqueezy.com/settings/webhooks).

##### Environment Variables

Pay will automatically look for the following environment variables, or the equivalent
Rails credentials:

* `LEMON_SQUEEZY_API_KEY`
* `LEMON_SQUEEZY_STORE_ID`
* `LEMON_SQUEEZY_SIGNING_SECRET`

## 2 Javascript

### Lemon Squeezy Javascript

Lemon.js is used for Lemon Squeezy. It is a Javascript library that allows you to embed
a checkout into your website.

#### Setup

Add the Lemon.js script in your application layout.

```html
<script src="https://app.lemonsqueezy.com/js/lemon.js" defer></script>
```

#### Generating a Checkout Button

With Lemon.js initialized, it will automatically look for any elements with the `lemonsqueezy-button`
class and turn them into a checkout button.

It doesn't support sending attributes, so to customize the checkout button and session, you'll need to
add additional parameters to the URL. You can view the [supported fields here](https://docs.lemonsqueezy.com/help/checkout/prefilling-checkout-fields) and the [custom data field here](https://docs.lemonsqueezy.com/help/checkout/passing-custom-data).

You can use the `Pay::LemonSqueezy.passthrough` helper to generate the `checkout[custom][passthrough]` field.

You'll need to replace `storename` with your store URL slug & `UUID` with the UUID of the plan you want to use, which
can be found by clicking Share on the product in Lemon Squeezy's dashboard.

```html
<a
  class="lemonsqueezy-button"
  href="https://storename.lemonsqueezy.com/checkout/buy/UUID?checkout[email]=<%= @user.email %>&checkout[custom][passthrough]=<%= Pay::LemonSqueezy.passthrough(owner: @user) %>">
  Sign up to Plan
</a>
```

#### Hosted Checkout

Hosted checkout is the default checkout method. It will open a new window to the Lemon Squeezy website.
If Lemon.js is loaded, and the `lemonsqueezy-button` class is added to the link, it will open the checkout
in an overlay.

#### Overlay Checkout

To enable overlay checkout, add `embed=1` to the above URL.

## 3 Webhooks

### Lemon Squeezy Webhooks

#### Endpoint

The webhook endpoint for Lemon Squeezy is `/pay/webhooks/lemon_squeezy` by default.

#### Events

Pay requires the following webhooks to properly sync charges and subscriptions as they happen.

```ruby
subscription_created
subscription_updated
subscription_payment_success
```

# Marketplaces

## Braintree

### Braintree Marketplace Payments

[Braintree Marketplace Overview](https://developers.braintreepayments.com/guides/braintree-marketplace/overview)

**Work In Progress**

Braintree marketplace payments are unfinished and may not work completely.

#### Usage

To add Merchant functionality to a model, configure the model:

```ruby
class User
	pay_merchant
end
```

##### Assigning a merchant to a customer

Payments for the billable will be processed through the sub-merchant account.

```ruby
@user.set_merchant_processor :braintree, processor_id: "provider_sub_merchant_account"
```

##### Creating a marketplace transaction

```ruby
@user.payment_processor.charge(10_00, service_fee_amount: "1.00")
```

Pay will store the `service_fee_amount` for transactions in the `application_fee_amount` field on `Pay::Charge`.

## Stripe Connect

### Stripe Connect

You can use Stripe Connect to handle Marketplace payments in your app.

There are two main marketplace payment types:

- Allow other businesses to accept payments directly from their customers (i.e. Shopify)
- Collect payments directly and pay out service providers separately (i.e. Lyft, Instacart, Postmates)

Not sure what account types to use? Read the Stripe docs: https://stripe.com/docs/connect/accounts

#### Usage

To add Merchant functionality to a model, configure the model:

```ruby
class User
  pay_merchant
end
```

#### Example

```ruby
@user = User.last

### Use Stripe for the Merchant
@user.set_merchant_processor :stripe

@user.merchant_processor.create_account
###=> Stripe::Account

@user.merchant_processor.account_link
@user.merchant_processor.login_link
@user.merchant_processor.transfer(amount: 25_00)
@user.merchant_processor.onboarding_complete? # Updates via webhook based on the Stripe::Account's #charges_enabled attribute
```

#### When Using Checkout Session

You can add your stripe connect account by passing the connect id to the set_payment_processor

```ruby
class SubscriptionsController < ApplicationController
  def checkout
    # Make sure the user's payment processor is Stripe
    current_user.set_payment_processor :stripe, stripe_account: "acct_1234"

    # One-time payments (https://stripe.com/docs/payments/accept-a-payment)
    @checkout_session = current_user.payment_processor.checkout(mode: "payment", line_items: "price_1ILVZaKXBGcbgpbZQ26kgXWG")

    # Or Subscriptions (https://stripe.com/docs/billing/subscriptions/build-subscription)
    @checkout_session = current_user.payment_processor.checkout(
      mode: 'subscription',
      locale: I18n.locale,
      line_items: [{
        price: 'price_1ILVZaKXBGcbgpbZQ26kgXWG',
        quantity: 4
      }],
      subscription_data: {
        trial_period_days: 15,
        metadata: {
          pay_name: "base" # Optional. Overrides the Pay::Subscription name attribute
        },
      },
      success_url: root_url,
      cancel_url: root_url
    )

    # Or Setup a new card for future use (https://stripe.com/docs/payments/save-and-reuse)
    @checkout_session = current_user.payment_processor.checkout(mode: "setup")

    # If you want to redirect directly to checkout
    redirect_to @checkout_session.url, allow_other_host: true, status: :see_other
  end
end
```

#### Charge Types

Stripe provides multiple ways of handling payments

| Charge Type                    | Use When                                                                                                                                                 |
| ------------------------------ | -------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Direct charges                 | Customers directly transact with your user, often unaware of your platform's existence                                                                   |
| Destination charges            | Customers transact with your platform for products or services provided by your user                                                                     |
| Separate charges and transfers | Multiple users are involved in the transaction <br />A specific user isn't known at the time of charge<br />Transfer can't be made at the time of charge |

##### Direct Charges

- You create a charge on your user’s account so the payment appears as a charge on the connected account, not in your account balance.
- The connected account’s balance increases with every charge.
- Your account balance increases with application fees from every charge.
- The connected account’s balance will be debited for the cost of Stripe fees, refunds, and chargebacks.

```ruby
@user.stripe_account = "acct_123l5jadsgfas3"
@user.charge(10_00, application_fee_amount: 1_23)
```

```javascript
var stripe = Stripe("<%= @sample_credentials.test_publishable_key %>", {
  stripeAccount: "{{CONNECTED_STRIPE_ACCOUNT_ID}}",
});
```

##### Destination Charges

- You create a charge on your platform’s account so the payment appears as a charge on your account. Then, you determine whether some or all of those funds are transferred to the connected account.
- Your account balance will be debited for the cost of the Stripe fees, refunds, and chargebacks.

```ruby
@user.charge(
  10_00,
  application_fee_amount: 1_23,
  transfer_data: {
    destination: '{{CONNECTED_STRIPE_ACCOUNT_ID}}'
  }
)
```

##### Separate Charges and Transfers

- You create a charge on your platform’s account and also transfer funds to your user’s account. The payment appears as a charge on your account and there’s also a transfer to a connected account (amount determined by you), which is withdrawn from your account balance.
- You can transfer funds to multiple connected accounts.
- Your account balance will be debited for the cost of the Stripe fees, refunds, and chargebacks.

```ruby
pay_charge = @user.charge(100_00, transfer_group: '{ORDER10}')

### Create a Transfer to a connected account (later):
@other_user.merchant_processor.transfer(
  amount: 70_00,
  transfer_group: '{ORDER10}',
)

### Create a second Transfer to another connected account (later):
@another_user.merchant_processor.transfer(
  amount: 20_00,
  transfer_group: '{ORDER10}',
)
```

Alternatively, the `source_transaction` parameter allows you to transfer only once a charge's funds are available. This helps to make sure the funds are available in your Stripe account before transferring.

See: https://stripe.com/docs/connect/charges-transfers#transfer-availability

```ruby
@other_user.merchant_processor.transfer(
  amount: 70_00,
  source_transaction: pay_charge.processor_id
)
```

##### Verification

By default, Pay sets up a webhook listener for the `account.updated` event that updates an `onboarding_complete` flag based on whether `charges_enabled` is true, which Stripe updates based on the account's current verification (or lack thereof) status as long as you request a charge or transfer capability when connecting the user's Stripe Connect account to your platform's Stripe account.

# Paddle Billing

## 1 Overview

### Using Pay with Paddle Billing

Paddle Billing is Paddle's new subscription billing platform. It differs quite a bit
from Paddle Classic. This guide will help you get started with implementing it in your
Rails application.

* Checkout only happens via iFrame or hosted page
* Cancelling a subscription cannot be resumed
* Payment methods can only be updated while a subscription is active

#### Creating Customers

Paddle now works similar to Stripe. You create a customer, which subscriptions belong to.

```ruby
### Set the payment processor
@user.set_payment_processor :paddle_billing

### Create the customer on Paddle
@user.payment_processor.api_record
```

#### Prices & Plans

Paddle introduced Products & Prices to support more payment options. Previously,
they Products and Plans separated.

#### Subscriptions

Paddle subscriptions are not created through the API, but through Webhooks. When a
subscription is created, Paddle will send a webhook to your application. Pay will
automatically create the subscription for you.

#### Configuration

##### Paddle API Key

You can generate an API key [here for Production](https://vendors.paddle.com/authentication-v2)
or [here for Sandbox](https://sandbox-vendors.paddle.com/authentication-v2)

##### Paddle Client Token

Client side tokens are used to work with Paddle.js in your frontend. You can generate one using the same links above.

##### Paddle Environment

Paddle has two environments: Sandbox and Production. To use the Sandbox environment,
set the Environment value to `sandbox`. By default, this is set to `production`.

##### Paddle Signing Secret

Paddle uses a signing secret to verify that webhooks are coming from Paddle. You can find
this after creating a webhook in the Paddle dashboard. You'll find this page
[here for Production](https://vendors.paddle.com/notifications) or
[here for Sandbox](https://sandbox-vendors.paddle.com/notifications).

##### Environment Variables

Pay will automatically look for the following environment variables, or the equivalent
Rails credentials:

- `PADDLE_BILLING_ENVIRONMENT`
- `PADDLE_BILLING_API_KEY`
- `PADDLE_BILLING_CLIENT_TOKEN`
- `PADDLE_BILLING_SIGNING_SECRET`

## 2 Javascript

### Paddle Javascript

Paddle.js v2 is used for Paddle Billing. It is a Javascript library that allows you to embed
Paddle Checkout into your website.

#### Setup

Add the Paddle.js script in your application layout and initialize it with your Paddle Client Side Token.

```html
<script src="https://cdn.paddle.com/paddle/v2/paddle.js"></script>
<script type="text/javascript">
  Paddle.Environment.set("sandbox");
  Paddle.Initialize({
    token: "<%= Pay::PaddleBilling.client_token %>"
  });
</script>
```

#### Generating a Checkout Button

With Paddle.js initialized, it will automatically look for any elements with the `paddle_button`
class and turn them into a checkout button.

It supports sending HTML Data Attributes to customize the checkout button and session.

You can view the [supported attributes here](https://developer.paddle.com/paddlejs/html-data-attributes).

In this example, the `data-customer-id` attribute is set to the Paddle Customer ID. This is used
to link the newly created subscription to this customer.

The `data-items` attribute requires an array of items for this checkout. It also requires a
`priceId` and `quantity` for each item.

```html
<a href='#'
  class='paddle_button'
  data-display-mode='overlay'
  data-theme='none'
  data-locale='en'
  data-items='[
    {
      "priceId": "<%= plan.price_id %>",
      "quantity": 1
    }
  ]'
  data-customer-id="<%= @user.payment_processor.processor_id %>"
>
  Sign up to <%= plan.name %>
</a>
```

#### Overlay Checkout

The overlay checkout is the default checkout method. It will open a modal on top of your website.

#### Inline Checkout

Inline checkout can be enabled by setting the `data-display-mode` attribute to `inline`. This allows
you to have tighter integration within your application.

For more information, see the [Paddle documentation](https://developer.paddle.com/build/checkout/build-branded-inline-checkout).

## 3 Webhooks

### Paddle Billing Webhooks

#### Endpoint

The webhook endpoint for Paddle Billing is `/pay/webhooks/paddle_billing` by default.

#### Events

Pay requires the following webhooks to properly sync charges and subscriptions as they happen.

```ruby
subscription.activated
subscription.canceled
subscription.created
subscription.imported
subscription.past_due
subscription.paused
subscription.resumed
subscription.trialing
subscription.updated

transaction.completed
```

# Paddle Classic

## 1 Overview

### Using Pay with Paddle Classic

Paddle works differently than most of the other payment processors so it comes with some limitations and differences.

* You cannot create a Customer from the API
* Checkout only happens via iFrame or hosted page
* Cancelling a subscription cannot be resumed
* Payment methods can only be updated while a subscription is active
* Paddle customers are not reused when a user re-subscribes

#### Paddle Sandbox

The [Paddle Sandbox](https://developer.paddle.com/getting-started/sandbox) can be used for testing your Paddle integration.

```html
<script src="https://cdn.paddle.com/paddle/paddle.js"></script>
<script type="text/javascript">
  Paddle.Environment.set('sandbox');
  Paddle.Setup({ vendor: <%= Pay::PaddleClassic.vendor_id %> });
</script>
```
#### Paddle Public Key

Paddle uses public/private keys for webhook verification. You can find
your public key [here for Production](https://vendors.paddle.com/public-key)
and [here for Sandbox](https://sandbox-vendors.paddle.com/public-key).

There are 3 ways that you can set the public key in Pay.

In either example, you can set the environment variable or in Rails credentials.

##### File

You can download the public key from the link above and save it to a location which your Rails application
can access. Then set the `PADDLE_CLASSIC_PUBLIC_KEY_FILE` to the location of the file.

##### Key

Set the `PADDLE_CLASSIC_PUBLIC_KEY` environment variable with your public key. Replace any spaces with `\n` otherwise
you may get a `OpenSSL::PKey::RSAError` error.

##### Base64 Encoded Key

Or you can set a Base64 encoded version of the key. To do this, download a copy of your public key
then open a `rails console` and enter the following:

```ruby
paddle_public_key = OpenSSL::PKey::RSA.new(File.read("paddle.pem"))
Base64.encode64(paddle_public_key.to_der)
```

Copy what's displayed and set the `PADDLE_CLASSIC_PUBLIC_KEY_BASE64` environment variable.

## 2 Javascript

### Paddle Classic Javascript

##### Update Payment Details

https://developer.paddle.com/guides/how-tos/subscriptions/update-payment-details

####### Inline

```html
<a href="#!" class="paddle_button"
   data-override="https://checkout.paddle.com/subscription/update..."
   data-success="https://example.com/subscription/update/success"
   >Update Payment Information</a>
```

```javascript
Paddle.Checkout.open({
  override: 'https://checkout.paddle.com/subscription/update...',
  success: 'https://example.com/subscription/update/success'
});
```

####### Overlay

```javascript
Paddle.Checkout.open({
    override: 'https://checkout.paddle.com/subscription/update...',
    method: 'inline',
    frameTarget: 'checkout-container', // The className of your checkout <div>
    frameInitialHeight: 416,
    frameStyle: 'width:100%; min-width:312px; background-color: transparent; border: none;',    // Please ensure the minimum width is kept at or above 312px.
    success: 'https://example.com/subscription/update/success'
});
```


## 3 Webhooks

### Paddle Classic Webhooks

#### Endpoint

The webhook endpoint for Paddle is `/pay/webhooks/paddle_classic` by default.

#### Events

Pay requires the following webhooks to properly sync charges and subscriptions as they happen.

```ruby
subscription_created
subscription_updated
subscription_cancelled
subscription_payment_succeeded
subscription_payment_refunded
```

# Stripe

## 1 Overview

### Using Pay with Stripe

Stripe has multiple options for payments

* [Stripe Checkout](https://stripe.com/payments/checkout) - Hosted pages for payments (you'll redirect users to Stripe)
* [Stripe Elements](https://stripe.com/payments/elements) - Payment fields on your site

#### Prices & Plans

Stripe introduced Products & Prices to support more payment options. Previously, they had a concept called Plan that was for subscriptions. Pay supports both `Price IDs` and `Plan IDs` when subscribing.

```ruby
@user.payment_processor.subscribe(plan: "price_1234")
@user.payment_processor.subscribe(plan: "plan_1234")
```

Multiple subscription items in a single subscription can be passed in as `items`:

```ruby
@user.payment_processor.subscribe(
  items: [
    {price: "price_1234"},
    {price: "price_5678"}
  ]
)
```

See: https://stripe.com/docs/api/subscriptions/create

#### Promotion Codes

Promotion codes are customer-facing coupon codes that can be applied in several ways.

You can apply a promotion code on the Stripe::Customer to have it automatically apply to all Subscriptions.

```ruby
@user.payment_processor.update_api_record(promotion_code: "promo_1234")
```

Promotion codes can also be applied directly to a subscription:
```ruby
@user.payment_processor.subscribe(plan: "plan_1234", promotion_code: "promo_1234")
```

Stripe Checkout can also accept promotion codes by enabling the flag:
```ruby
@checkout_session = current_user.payment_processor.checkout(
  mode: "payment",
  line_items: "price_1ILVZaKXBGcbgpbZQ26kgXWG",
  allow_promotion_codes: true
)
```

#### Failed Payments

Subscriptions that fail payments will be set to `past_due` status.

If all attempts are exhausted, Stripe will either leave the subscription as `past_due`, `canceled`, or set it as `unpaid` depending on the settings in your Stripe account.

We recommend marking subscriptions as `unpaid`. Pay treats this subscription as inactive. You can display it and allow the user to pay their outstanding invoice in order to resume their subscription.

For metered billing, this is helpful since invoices aren't issued until the customer has used your product. If you allow them to resubscribe without paying the outstanding invoice, they could use your product for free. You should force them to pay the outstanding invoice instead of allowing them to start a new subscription.

For standard billing, the user pre-pays for a month. They can resume the `unpaid` subscription or start a new subscription without over/under charging them.

#### Stripe Terminal

Collecting in-person payments with Stripe Terminal is also easy with Pay. You can use the `terminal_charge` method to create a charge with the `card_present` payment method type and manual capture to be used with Terminal.

```ruby
payment_intent = current_user.payment_processor.terminal_charge(10_00)
```

#### Next

See [Credentials](#2-credentials)

## 2 Credentials

### Stripe Credentials

To use Stripe with Pay, you'll need to add your API keys and Signing Secret(s) to your Rails app. See [Configuring Pay](#credentials) for instructions on adding credentials or ENV Vars.

##### API keys

You can create (or find) your Stripe private (secret) and public (publishable) keys in the [Stripe Dashboard](https://dashboard.stripe.com/test/apikeys).

>[!NOTE]
>
> By default we're linking to the "test mode" page for API keys so you can get up and running in development. When you're ready to deploy to production, you'll have to toggle the "test mode" option off and repeat all steps again for live payments.

##### Signing secrets

Webhooks use signing secrets to verify the webhook was sent by Stripe. Check out [Webhooks](#enable-stripe-webhooks) doc for detailed instructions on where/how to get these.

###### Dashboard

The [Webhooks](https://dashboard.stripe.com/test/webhooks/) page on Stripe contains all the defined endpoints and their signing secrets.

###### Stripe CLI (Development)

View the webhook signing secret used by the Stripe CLI by running:

```sh
stripe listen --print-secret
```

#### Next

See [JavaScript](#3-javascript)

## 3 Javascript

### Stripe JavaScript

Here's some example Javascript for handling your payment forms with [Stripe.js](https://docs.stripe.com/js) and [Hotwire / Turbo](https://hotwired.dev).

###### Form HTML

With SCA, each of your actions client-side need a PaymentIntent or SetupIntent ID depending on what you're doing. If you're charging a card immediately, you must provide a PaymentIntent ID. For trials or updating the card on file, you should use a SetupIntent ID.

We recommend setting these IDs as data attributes on your `form`.

You can use  `data-payment-intent` or `data-setup-intent` depending on if you're making a payment (PaymentIntent) or setting up a card to use later (SetupIntent).

```rb
### Your controller if you are using a SetupIntent:

def new
  ...
  @setup_intent = current_user.payment_processor.create_setup_intent
  ...
end
```

```erb
<%= form_with url: subscription_path,
  id: "payment-form",
  data: {
    payment_intent: @payment_intent,
    setup_intent: @setup_intent.client_secret
  } do |form| %>

  <label>Credit or debit card</label>
  <div id="card-element" class="field"></div>

  <%= form.submit %>
<% end %>
```

Make sure any payment forms have `id="payment-form"` on them. This is how the Javascript finds the form to add Stripe to it.

Card fields should have an ID of `id="card-element"` to denote trigger Stripe JS to be applied to the form.

###### Stripe Public Key

A meta tag with `name="stripe-key"` should include the Stripe public key as the `content` attribute.

```erb
<%= tag.meta name: "stripe-key", content: Pay::Stripe.public_key %>
<script src="https://js.stripe.com/v3/" defer></script>
```

###### Javascript

When a form is submitted, the card will be tokenized into a Payment Method ID and submitted as a hidden field in the form.

```javascript
document.addEventListener("turbo:load", () => {
  let cardElement = document.querySelector("#card-element")

  if (cardElement !== null) { setupStripe() }

  // Handle users with existing card who would like to use a new one
  let newCard = document.querySelector("#use-new-card")
  if (newCard !== null) {
    newCard.addEventListener("click", (event) => {
      event.preventDefault()
      document.querySelector("#payment-form").classList.remove("d-none")
      document.querySelector("#existing-card").classList.add("d-none")
    })
  }
})

function setupStripe() {
  const stripe_key = document.querySelector("meta[name='stripe-key']").getAttribute("content")
  const stripe = Stripe(stripe_key)

  const elements = stripe.elements()
  const card = elements.create('card')
  card.mount('#card-element')

  var displayError = document.getElementById('card-errors')

  card.addEventListener('change', (event) => {
    if (event.error) {
      displayError.textContent = event.error.message
    } else {
      displayError.textContent = ''
    }
  })

  const form = document.querySelector("#payment-form")
  let paymentIntentId = form.dataset.paymentIntent
  let setupIntentId = form.dataset.setupIntent

  if (paymentIntentId) {
    if (form.dataset.status == "requires_action") {
      stripe.confirmCardPayment(paymentIntentId, { setup_future_usage: 'off_session' }).then((result) => {
        if (result.error) {
          displayError.textContent = result.error.message
          form.querySelector("#card-details").classList.remove("d-none")
        } else {
          form.submit()
        }
      })
    }
  }

  form.addEventListener('submit', (event) => {
    event.preventDefault()

    let name = form.querySelector("#name_on_card").value
    let data = {
      payment_method_data: {
        card: card,
        billing_details: {
          name: name,
        }
      }
    }

    // Complete a payment intent
    if (paymentIntentId) {
      stripe.confirmCardPayment(paymentIntentId, {
        payment_method: data.payment_method_data,
        setup_future_usage: 'off_session',
        save_payment_method: true,
      }).then((result) => {
        if (result.error) {
          displayError.textContent = result.error.message
          form.querySelector("#card-details").classList.remove("d-none")
        } else {
          form.submit()
        }
      })

    // Updating a card or subscribing with a trial (using a SetupIntent)
    } else if (setupIntentId) {
      stripe.confirmCardSetup(setupIntentId, {
        payment_method: data.payment_method_data
      }).then((result) => {
        if (result.error) {
          displayError.textContent = result.error.message
        } else {
          addHiddenField(form, "payment_method_token", result.setupIntent.payment_method)
          form.submit()
        }
      })

    } else {
      // Subscribing with no trial
      data.payment_method_data.type = 'card'
      stripe.createPaymentMethod(data.payment_method_data).then((result) => {
        if (result.error) {
          displayError.textContent = result.error.message
        } else {
          addHiddenField(form, "payment_method_token", result.paymentMethod.id)
          form.submit()
        }
      })
    }
  })
}

function addHiddenField(form, name, value) {
  let input = document.createElement("input")
  input.setAttribute("type", "hidden")
  input.setAttribute("name", name)
  input.setAttribute("value", value)
  form.appendChild(input)
}
```

#### Next

See [Strong Customer Authentication (SCA)](#4-sca)

## 4 Sca

### Stripe Strong Customer Authentication (SCA)

Our Stripe integration **requires** the use of Payment Method objects to correctly support Strong Customer Authentication with Stripe. If you've previously been using card tokens, you'll need to upgrade your Javascript integration.

Subscriptions that require SCA are marked as `incomplete` by default.
Once payment is authenticated, Stripe will send a webhook updating the
status of the subscription. You'll need to use the [Stripe CLI](https://github.com/stripe/stripe-cli) to forward
webhooks to your application to make sure your subscriptions work
correctly for SCA payments.

```bash
stripe listen --forward-to localhost:3000/pay/webhooks/stripe
```

You should use `stripe.confirmCardSetup` on the client to collect card information anytime you want to save the card and charge them later (adding a card, then charging them on the next page for example). Use `stripe.confirmCardPayment` if you'd like to charge the customer immediately (think checking out of a shopping cart).

The Javascript also needs to have a PaymentIntent or SetupIntent created server-side and the ID passed into the Javascript to do this. That way it knows how to safely handle the card tokenization if it meets the SCA requirements.

#### **SCA Payment Confirmations**

Sometimes you'll have a payment that requires extra authentication. In this case, Pay provides a webhook and action for handling these payments. It will automatically email the customer and provide a link with the PaymentIntent ID in the url where the customer will be asked to fill out their name and card number to confirm the payment. Once done, they'll be redirected back to your application.

##### Pay::ActionRequired

When a charge or subscription needs SCA confirmation, Pay will raise a `Pay::ActionRequired` error. You can use this to redirect to the SCA confirm page.

```ruby
def create
  @user.charge(10_00)
  # or @user.subscribe(plan: "x")

rescue Pay::ActionRequired => e
  # Redirect to the Pay SCA confirmation page
  redirect_to pay.payment_path(e.payment.id)

rescue Pay::Error => e
  # Display any other errors
  flash[:alert] = e.message
  render :new, status: :unprocessable_entity
end
```

##### Stripe SCA Confirm Page

We provide a route for confirming Stripe SCA payments at `/pay/payments/:payment_intent_id`.

If you'd like to change the views of the payment confirmation page, you can install the views using the generator and modify the template.

[<img src="https://d1jfzjx68gj8xs.cloudfront.net/items/2s3Z0J3Z3b1J1v2K2O1a/Screen%20Shot%202019-10-10%20at%2012.56.32%20PM.png?X-CloudApp-Visitor-Id=51470" alt="Stripe SCA Payment Confirmation" style="zoom: 25%;" />](https://d1jfzjx68gj8xs.cloudfront.net/items/2s3Z0J3Z3b1J1v2K2O1a/Screen%20Shot%202019-10-10%20at%2012.56.32%20PM.png)

If you use the default views for payment confirmations, and also have a Content Security Policy in place for your application, make sure to add the following domains to their respective configurations in your `content_security_policy.rb` (otherwise these views won't load properly):

* `style_src`: `https://unpkg.com`
* `script_src`: `https://unpkg.com` and `https://js.stripe.com`
* `frame_src`: `https://js.stripe.com`

#### Next

See [Webhooks](#5-webhooks)

## 5 Webhooks

### Stripe Webhooks

Pay listens to Stripe's webhooks to keep the local payments data in sync. 

For development, we use the Stripe CLI to forward webhooks to our local server. 
In production, webhooks are sent directly to our app's domain.

#### Development webhooks with the Stripe CLI

You can use the [Stripe CLI](https://stripe.com/docs/stripe-cli) to test and forward webhooks in development.

```bash
stripe login
stripe listen --forward-to localhost:3000/pay/webhooks/stripe
```

#### Production webhooks for Stripe

1. Visit https://dashboard.stripe.com/webhooks/create.
2. Use the default "Add an endpoint" form.
3. Set "endpoint URL" to https://example.org/pay/webhooks/stripe (Replace `example.org` with your domain)
4. Under "select events to listen to" choose "Select all events" and click "Add events". Or if you want to listen to specific events, check out [events we listen to](#events).
5. Finalize the creation of the endpoint by clicking "Add endpoint".
6. After creating the webhook endpoint, click "Reveal" under the heading "Signing secret". Copy the `whsec_... ` value to wherever you have configured your keys for Stripe as instructed in [Credentials](#credentials) section under Configurations doc.

#### Events

Pay requires the following webhooks to properly sync charges and subscriptions as they happen.

```ruby
charge.succeeded
charge.refunded

payment_intent.succeeded

invoice.upcoming
invoice.payment_action_required

customer.subscription.created
customer.subscription.updated
customer.subscription.deleted
customer.subscription.trial_will_end
customer.updated
customer.deleted

payment_method.attached
payment_method.updated
payment_method.automatically_updated
payment_method.detached

account.updated

checkout.session.completed
checkout.session.async_payment_succeeded
```

[Click here](https://dashboard.stripe.com/webhooks/create?events=charge.succeeded%2Ccharge.refunded%2Cpayment_intent.succeeded%2Cinvoice.upcoming%2Cinvoice.payment_action_required%2Ccustomer.subscription.created%2Ccustomer.subscription.updated%2Ccustomer.subscription.deleted%2Ccustomer.subscription.trial_will_end%2Ccustomer.updated%2Ccustomer.deleted%2Cpayment_method.attached%2Cpayment_method.updated%2Cpayment_method.automatically_updated%2Cpayment_method.detached%2Caccount.updated%2Ccheckout.session.completed%2Ccheckout.session.async_payment_succeeded) to create a new Stripe webhook with all the events pre-filled.

#### Next

See [Metered Billing](#6-metered-billing)

## 6 Metered Billing

### Stripe Metered Billing

Metered billing are subscriptions where the price fluctuates monthly. For example, you may spin up servers on DigitalOcean, shut some down, and keep others running. Metered billing allows you to report usage of these servers and charge according to what was used.

```ruby
@user.payment_processor.subscribe(plan: "price_metered_billing_id")
```

This will create a new metered billing subscription. You can then create meter events to bill for usage:

```ruby
@user.payment_processor.create_meter_event(:api_request, payload: { value: 1 })
```

If your price is using the legacy usage records system, you will need to use the below method:

```ruby
pay_subscription.create_usage_record(quantity: 99)
```

If your subscription has multiple SubscriptionItems, you can specify the `subscription_item_id` to be used:

```ruby
pay_subscription.create_usage_record(subscription_item_id: "si_1234", quantity: 99)
```

#### Failed Payments

If a metered billing subscription fails, it will fall into a `past_due` state.

After payment attempts fail, Stripe will either leave the subscription alone, cancel it, or mark it as `unpaid` depending on the settings in your Stripe account.
We recommend marking the subscription as `unpaid`.

You can notify your user to update their payment method. Once they do, you can retry the open payment to bring their subscription back into the active state.

#### Next

See [Stripe Tax](#7-stripe-tax)

## 7 Stripe Tax

### Stripe Tax

Collecting tax is easy with Stripe and Pay. You'll need to enable Stripe Tax in the dashboard and configure your Tax registrations where you're required to collect tax.

##### Set Address on Customer

An address is required on the Customer for tax calculations.

```ruby
class User < ApplicationRecord
  pay_customer stripe_attributes: :stripe_attributes

  def stripe_attributes(pay_customer)
    {
      address: {
        country: "US",
        postal_code: "90210"
      }
    }
  end
end
```

To update the customer address anytime it's changed, call the following method:

```ruby
@user.payment_processor.update_api_record
```

This will make an API request to update the Stripe::Customer with the current `stripe_attributes`.

See the Stripe Docs for more information about update tax addresses on a customer.
https://stripe.com/docs/api/customers/update#update_customer-tax-ip_address

##### Subscribe with Automatic Tax

To enable tax for a subscription, you can pass in `automatic_tax`:

```ruby
@user.payment_processor.subscribe(plan: "growth", automatic_tax: { enabled: true })
```

For Stripe Checkout, you can do the same thing:

```ruby
@user.payment_processor.checkout(mode: "payment", line_items: "price_1234", automatic_tax: { enabled: true })
@user.payment_processor.checkout(mode: "subscription", line_items: "price_1234", automatic_tax: { enabled: true })
```

##### Pay::Charges

Taxes are saved on the `Pay::Charge` model.

* `tax` - the total tax charged
* `total_tax_amounts` - The tax rates for each jurisidction on the charge

#### Next

See [Stripe Checkout & Billing Portal](#8-stripe-checkout)

## 8 Stripe Checkout

### Stripe Checkout

[Stripe Checkout](https://stripe.com/docs/payments/checkout) allows you to simply redirect to Stripe for handling payments. The main benefit is that it's super fast to setup payments in your application, they're SCA compatible, and they will get improved automatically by Stripe.

> [!WARNING]
> You need to configure webhooks before using Stripe Checkout otherwise your application won't be updated with the correct data.
>
> See [Webhooks](/docs/stripe/5_webhooks.md) section on how to do that.

![stripe checkout example](https://i.imgur.com/nFsCBCK.gif)

##### How to use Stripe Checkout with Pay

Choose the checkout button mode you need and pass any required arguments. Read the [Stripe Checkout Session API docs](https://stripe.com/docs/api/checkout/sessions/create) to see what options are available. For instance:

```ruby
class SubscriptionsController < ApplicationController
  def checkout
    # Make sure the user's payment processor is Stripe
    current_user.set_payment_processor :stripe

    # One-time payments (https://stripe.com/docs/payments/accept-a-payment)
    @checkout_session = current_user.payment_processor.checkout(mode: "payment", line_items: "price_1ILVZaKXBGcbgpbZQ26kgXWG")

    # Or Subscriptions (https://stripe.com/docs/billing/subscriptions/build-subscription)
    @checkout_session = current_user.payment_processor.checkout(
      mode: 'subscription',
      locale: I18n.locale,
      line_items: [{
        price: 'price_1ILVZaKXBGcbgpbZQ26kgXWG',
        quantity: 4
      }],
      subscription_data: {
        trial_period_days: 15,
        metadata: {
          pay_name: "base" # Optional. Overrides the Pay::Subscription name attribute
        },
      },
      success_url: root_url,
      cancel_url: root_url
    )

    # Or Setup a new card for future use (https://stripe.com/docs/payments/save-and-reuse)
    @checkout_session = current_user.payment_processor.checkout(mode: "setup")

    # If you want to redirect directly to checkout
    # redirect_to @checkout_session.url, allow_other_host: true, status: :see_other
  end
end
```

Then link to it in your view:

```erb
<%= link_to "Checkout", @checkout_session.url %>
```

> [!NOTE]
> Due to a [bug](https://github.com/hotwired/turbo/issues/211#issuecomment-966570923) in the browser's `fetch` implementation, you will need to disable Turbo if redirecting to Stripe checkout server-side.
>
> ```erb
> <%= link_to "Checkout", checkout_path, data: { turbo: false } %>
> ```

The `stripe_checkout_session_id` param will be included on success and cancel URLs automatically. This allows you to lookup the checkout session on your success page and confirm the payment was successful before fulfilling the customer's purchase.

https://stripe.com/docs/payments/checkout/custom-success-page

#### Stripe Customer Billing Portal

Customers will want to update their payment method, subscription, etc. This can be done with the [Customer Billing Portal](https://stripe.com/docs/billing/subscriptions/integrating-customer-portal). It works the same as the other Stripe Checkout pages.

First, create a session in your controller:

```ruby
class SubscriptionsController < ApplicationController
  def index
    @portal_session = current_user.payment_processor.billing_portal

    # You can customize the billing_portal return_url (default is root_url):
    # @portal_session = current_user.payment_processor.billing_portal(return_url: your_url)
  end
end
```

Then link to it in your view:

```erb
<%= link_to "Billing Portal", @portal_session.url %>
```

Or redirect to it in your controller:

```ruby
redirect_to @portal_session.url, allow_other_host: true, status: :see_other
```

#### Fulfilling orders after Checkout completed

For one-time payments, you'll need to add a webhook listener for the Checkout `stripe.checkout.session.completed` and `stripe.checkout.session.async_payment_succeeded` events. Some payment methods are delayed so you need to verify the `payment_status == "paid"`. The async payment succeeded event fires when delayed payments are complete.

For subscriptions, Pay will automatically create the `Pay::Subscription` record for you.

To create custom webhook listeners for specific events, you can create your custom webhook listener classes under a folder like `app/webhooks`, like this:
```ruby
### app/webhooks/fulfill_checkout.rb

class FulfillCheckout
  def call(event)
    object = event.data.object

    return if object.payment_status != "paid"

    # Handle fulfillment
  end
end
```

And then subscribe your custom webhook listener class to specific Stripe events on `config/initializers/pay.rb`:
```ruby
ActiveSupport.on_load(:pay) do
  Pay::Webhooks.delegator.subscribe "stripe.checkout.session.completed", FulfillCheckout.new
  Pay::Webhooks.delegator.subscribe "stripe.checkout.session.async_payment_succeeded", FulfillCheckout.new
end
```

That's it!

## 9 Customer Reconciliation

### Stripe customer reconciliation
Pay tracks customers for each payment processor using the `Pay::Customer` model, but the payment processor logic for customers varies between providers. When using Stripe with Pay, a customer object must exist for a model with `pay_customer` for charges and subscriptions to occur. If a `Pay::Customer` does not exist, one will be created automatically when attempting to operate upon subscriptions and charges.

When creating the new `Pay::Customer`, Pay does not attempt to reconcile the attributes used to create a `Pay::Customer` with existing Stripe customers. As a result, there is a possibility that duplicate Stripe customers may exist with the same attributes (e.g. email) if the application using Pay does not manually reconcile existing Stripe customers with the `Pay::Customer` s.

##### Manual reconciliation
The Stripe API can be used to list all existing Stripe customers. This allows the application to implement the necessary logic for creating and associating `Pay::Customer` s within the application.

There are two methods available to associate existing Stripe customers with a `pay_customer` model.

* `Model.set_payment_processor`: Finds or creates a `Pay::Customer` and marks it as the default for the model (the default `Pay::Customer` is the `Model.payment_processor`). It also removes the default flag from other `Pay::Customer`s and `Pay::PaymentMethod`s. Example: `User.set_payment_processor("stripe", processor_id: "cus_O1PngYajzbTEST")`
* `Model.add_payment_processor`: Finds or creates a `Pay::Customer`, updating the `Pay::Customer` with the attributes provided. This method does not mutate default flags for existing `Pay::Customer`s that exist. Example: `User.add_payment_processor("stripe", processor_id: "cus_O1PngYajzbTEST")`. 

##### Automated reconciliation
Automated reconciliation is possible through the use of ActiveRecord callbacks.

*Note*: Care should be taken with automated reconciliation, as automated reconciliation may have security and privacy implications on your application. Automatically associating a Pay customer to a `pay_customer` model based on unverified attributes could be used to abuse the existing payment methods. An example of such a situation would be automatically associating a Pay customer based on an email address of a user, where the user is not required to verify the email prior to authentication.

###### One-to-one reconciliation
To automatically reconcile an existing Stripe customer with a `pay_customer` model, the following example can be modified to search for an existing Stripe customer by email address, and if one exists, it will be added as the default payment processor. If more than one Stripe customer exists with the same email address, none of the existing customers will be associated, and a new Stripe customer will be created by Pay when necessary.

```ruby
class User < ActiveRecord
  after_create :reconcile_stripe_customer

  def reconcile_stripe_customer
    # Find all customers with the same email address
    stripe_customers = ::Stripe::Customer.list(email: self.email)["data"]

    # If there is more than one existing customer or no existing customer,
    # do nothing, otherwise add the customer as the default payment processor
    return if stripe_customers.length != 1

    self.set_payment_processor("stripe", processor_id: stripe_customers[0]["id"])
  end
end
```

###### One-to-many reconciliation
To automatically reconcile multiple existing Stripe customers with a `pay_customer` model after a new record is created, the following example can be modified to search for existing Stripe customers by email address, and if any exist, they will be added as a `Pay::Customer`. The last customer created will be the default payment processor if none previously existed.

```ruby
class User < ActiveRecord
  after_create :reconcile_stripe_customers

  def reconcile_stripe_customers
    # Find all customers with the same email address
    Stripe::Customer.list(email: self.email).auto_paging_each do |customer|
      # Create the pay customer, associating it to the current user
      Pay::Customer.create(owner: self, processor: "stripe", processor_id: customer["id"])
    end
  end
end
```

##### Backfilling subscriptions and charges for reconciled customers
When `Pay::Customer`s are created using `Model.set_payment_processor` or `Model.add_payment_processor`, existing Stripe subscriptions and charges are not automatically backfilled.

To backfill active subscriptions and the charges associated with those subscriptions, the `@user.payment_processor.sync_subscriptions` method can be used. To backfill all subscriptions including canceled subscriptions, the `status: "all"` parameter can be provided (e.g. `@user.payment_processor.sync_subscriptions(status: "all")`).

An equivalent method to backfilling charges not associated with subscriptions is not currently implemented within Pay, however `Pay::Charge`s can be created manually by the application such as in the example below.

```ruby
Stripe::Charge.list.auto_paging_each { |charge| Pay::Stripe::Charge.sync(charge.id) }
```
