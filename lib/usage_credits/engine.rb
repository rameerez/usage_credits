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

    # Add has_credits method to ActiveRecord::Base
    initializer "usage_credits.active_record" do
      ActiveSupport.on_load(:active_record) do
        extend UsageCredits::HasWallet::ClassMethods
      end
    end

    initializer "usage_credits.pay_integration" do
      ActiveSupport.on_load(:pay) do
        ::Pay::Subscription.include UsageCredits::SubscriptionExtension
        ::Pay::Charge.include UsageCredits::ChargeExtension
      end
    end

    config.to_prepare do
      Pay::Subscription.include UsageCredits::SubscriptionExtension
      Pay::Charge.include UsageCredits::ChargeExtension
    end


    initializer "usage_credits.configs" do
      # Initialize any config settings
    end
  end
end
