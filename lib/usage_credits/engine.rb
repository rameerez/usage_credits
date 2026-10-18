# frozen_string_literal: true

module UsageCredits
  # Rails engine for UsageCredits
  class Engine < ::Rails::Engine
    isolate_namespace UsageCredits

    # All gem code is required eagerly by lib/usage_credits.rb. Adding these
    # directories to the host app's autoloaders would make Zeitwerk claim
    # common top-level constants such as ::Wallet and ::Operation.

    # Add has_credits method to ActiveRecord::Base
    initializer "usage_credits.active_record" do
      ActiveSupport.on_load(:active_record) do
        extend UsageCredits::HasWallet::ClassMethods
      end
    end

    initializer "usage_credits.pay_integration" do
      ActiveSupport.on_load(:pay) do
        Pay::Subscription.include UsageCredits::PaySubscriptionExtension
        Pay::Charge.include UsageCredits::PayChargeExtension
      end
    end

    initializer "usage_credits.action_view" do
      ActiveSupport.on_load :action_view do
        require "usage_credits/helpers/credits_helper"
        include UsageCredits::CreditsHelper
      end
    end
  end
end
