# frozen_string_literal: true

module UsageCredits
  # Railtie for Rails integration
  class Railtie < Rails::Railtie
    railtie_name :usage_credits

    # Add rake tasks if any
    rake_tasks do
      path = File.expand_path(__dir__)
      Dir.glob("#{path}/tasks/**/*.rake").each { |f| load f }
    end

    # Add custom configuration options to Rails configuration
    config.usage_credits = UsageCredits.configuration

    # Initialize configuration defaults
    initializer "usage_credits.configure" do |app|
      UsageCredits.configure do |config|
        # TODO: error
        # config.logger = Rails.logger
      end
    end

    # Set up action view helpers if needed
    initializer "usage_credits.action_view" do
      ActiveSupport.on_load :action_view do
        require "usage_credits/helpers/credits_helper"
        include UsageCredits::CreditsHelper
      end
    end

    # Add custom middleware if needed
    initializer "usage_credits.middleware" do |app|
      # app.middleware.use UsageCredits::Middleware::CreditTracker
    end

    # Configure generators
    config.app_generators do |g|
      g.templates.unshift File::expand_path('../templates', __FILE__)
    end

    # Add custom subscribers for instrumentation
    config.after_initialize do
      # TODO: uninitialized constant UsageCredits::Instrumentation
      # UsageCredits::Instrumentation.subscribe_to_all_events
    end
  end
end
