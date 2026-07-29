# frozen_string_literal: true

require "test_helper"
require "open3"

module UsageCredits
  class EngineTest < ActiveSupport::TestCase
    test "gem code is not added to the host app autoloaders" do
      gem_lib = UsageCredits::Engine.root.join("lib").to_s

      Rails.autoloaders.each do |autoloader|
        autoloader.dirs.each do |dir|
          refute dir.to_s.start_with?(gem_lib), "#{dir} must not be autoloaded from usage_credits"
        end
      end
    end

    test "all gem constants are eagerly available without autoloading" do
      assert defined?(UsageCredits::Wallet)
      assert defined?(UsageCredits::Transaction)
      assert defined?(UsageCredits::Allocation)
      assert defined?(UsageCredits::Transfer)
      assert defined?(UsageCredits::Fulfillment)
      assert defined?(UsageCredits::HasWallet)
    end

    test "active record models gain the has_credits macro" do
      assert_respond_to ActiveRecord::Base, :has_credits
      assert_respond_to User, :has_credits
    end

    test "Pay models receive usage credits extensions through the engine hook" do
      assert_includes Pay::Charge.included_modules, UsageCredits::PayChargeExtension
      assert_includes Pay::Subscription.included_modules, UsageCredits::PaySubscriptionExtension
    end

    test "usage credits railtie require path remains available for compatibility" do
      assert_nothing_raised { require "usage_credits/railtie" }
      assert_same UsageCredits::Engine, UsageCredits::Railtie
    end

    test "usage credits railtie can be required directly" do
      script = 'require "bundler/setup"; require "usage_credits/railtie"; abort unless UsageCredits::Railtie == UsageCredits::Engine'
      _stdout, stderr, status = Open3.capture3(
        RbConfig.ruby,
        "-I", UsageCredits::Engine.root.join("lib").to_s,
        "-e", script
      )

      assert status.success?, stderr
    end
  end
end
