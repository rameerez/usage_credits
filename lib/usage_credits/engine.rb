# frozen_string_literal: true

module UsageCredits
  # Rails engine for UsageCredits
  class Engine < ::Rails::Engine
    isolate_namespace UsageCredits

    # Set up autoloading paths
    initializer "usage_credits.autoload", before: :set_autoload_paths do |app|
      app.config.autoload_paths << root.join("lib")
      app.config.autoload_paths << root.join("lib/usage_credits/models")
      app.config.autoload_paths << root.join("lib/usage_credits/models/concerns")
    end

    config.generators do |g|
      g.test_framework :rspec
      g.fixture_replacement :factory_bot
      g.factory_bot dir: "spec/factories"
    end

    # Add has_credits method to ActiveRecord::Base
    initializer "usage_credits.active_record" do
      ActiveSupport.on_load(:active_record) do
        extend UsageCredits::HasWallet::ClassMethods
      end
    end

    initializer "usage_credits.pay_integration" do
      ActiveSupport.on_load(:pay) do
        ::Pay::Subscription.include UsageCredits::SubscriptionExtension
      end
    end

    # Set up webhook handlers for Pay integration
    config.after_initialize do
      Pay::Webhooks.delegator.subscribe "stripe.checkout.session.completed" do |event|
        UsageCredits::Webhooks::StripeHandler.handle_checkout_completed(event)
      end

      Pay::Webhooks.delegator.subscribe "stripe.subscription.created" do |event|
        UsageCredits::Webhooks::StripeHandler.handle_subscription_created(event)
      end

      Pay::Webhooks.delegator.subscribe "stripe.subscription.updated" do |event|
        UsageCredits::Webhooks::StripeHandler.handle_subscription_updated(event)
      end

      Pay::Webhooks.delegator.subscribe "stripe.subscription.deleted" do |event|
        UsageCredits::Webhooks::StripeHandler.handle_subscription_deleted(event)
      end
    end
  end
end
