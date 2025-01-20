# frozen_string_literal: true

require "test_helper"

module UsageCredits
  class SubscriptionCreditTest < ActiveSupport::TestCase
    setup do
      @user = users(:default)
      @wallet = @user.credit_wallet

      # Define a test subscription rule
      UsageCredits.configure do |config|
        config.subscription_plan :test_plan do
          gives 1000.credits
          signup_bonus 100.credits
          trial_includes 50.credits
          unused_credits :rollover
        end

        config.subscription_plan :no_rollover_plan do
          gives 1000.credits
          unused_credits :expire
        end
      end
    end

    ############################
    # Subscription Plan Rules #
    ############################

    test "subscription plan rules are properly configured" do
      rule = UsageCredits.subscription_rules[:test_plan]
      assert_equal 1000, rule.monthly_credits
      assert_equal 100, rule.initial_credits
      assert_equal 50, rule.trial_credits
      assert rule.rollover_enabled
    end

    test "subscription plan can be configured without trial credits" do
      UsageCredits.configure do |config|
        config.subscription_plan :no_trial_plan do
          gives 1000.credits
        end
      end

      rule = UsageCredits.subscription_rules[:no_trial_plan]
      assert_equal 0, rule.trial_credits
    end

    test "subscription plan can be configured without rollover" do
      rule = UsageCredits.subscription_rules[:no_rollover_plan]
      assert_not rule.rollover_enabled
    end

    #########################
    # Trial Credit Handling #
    #########################

    test "credits are only given when subscription becomes active" do
      customer = create_customer
      subscription = Pay::Subscription.create!(
        customer: customer,
        processor_id: "sub_#{SecureRandom.hex(8)}",
        processor_plan: :test_plan,
        status: "incomplete",  # Payment not confirmed yet
        name: "default"
      )

      assert_equal 0, @user.credits # No credits given yet

      subscription.update!(status: "active")  # Payment confirmed
      assert_equal 1100, @user.credits # Now credits are given (1000 monthly + 100 signup)
    end

    test "trial credits are given when subscription starts trial" do
      subscription = create_subscription(trial_ends_at: 1.month.from_now)
      assert_equal 50, @user.credits # Only trial credits

      transaction = @user.credit_history.last
      assert_equal "subscription_trial", transaction.category
      assert_equal subscription.id, transaction.metadata["subscription_id"]
      assert_equal subscription.trial_ends_at.to_i, transaction.expires_at.to_i
    end

    ############################
    # Regular Credit Handling #
    ############################

    test "signup bonus is given when subscription starts" do
      subscription = create_subscription
      rule = UsageCredits.subscription_rules[:test_plan]

      rule.apply_to_subscription(subscription)

      bonus_transaction = @user.credit_history.by_category(:subscription_signup_bonus).last
      assert_equal 100, bonus_transaction.amount
      assert_equal subscription.id, bonus_transaction.metadata["subscription_id"]
    end

    test "monthly credits are given with rollover enabled" do
      subscription = create_subscription

      # Give some existing credits
      @user.give_credits(500, reason: "existing")

      subscription.update!(status: "active")
      assert_equal 1600, @user.credits # 500 existing + 100 signup + 1000 monthly

      monthly_transaction = @user.credit_history.by_category(:subscription_monthly).last
      assert_equal 1000, monthly_transaction.amount
    end

    test "monthly credits reset balance when rollover disabled" do
      subscription = create_subscription(plan: :no_rollover_plan)

      # Give some existing credits
      @user.give_credits(500, reason: "existing")

      subscription.update!(status: "active")
      assert_equal 1000, @user.credits # Previous credits are cleared

      reset_transaction = @user.credit_history.by_category(:subscription_monthly_reset).last
      assert_equal 1000, reset_transaction.amount
    end

    #######################
    # Credit Expiration #
    #######################

    test "credits can be configured to expire after cancellation" do
      UsageCredits.configure do |config|
        config.subscription_plan :expiring_plan do
          gives 1000.credits
          expire_after 30.days
        end
      end

      rule = UsageCredits.subscription_rules[:expiring_plan]
      assert rule.expire_credits_on_cancel
      assert_equal 30.days.to_i, rule.credit_expiration_period
    end

    #######################
    # Pay Integration #
    #######################

    test "credits expire when subscription is cancelled with expiration" do
      UsageCredits.configure do |config|
        config.subscription_plan :expiring_plan do
          gives 1000.credits
          expire_after 30.days
        end
      end

      customer = create_customer
      subscription = Pay::Subscription.create!(
        customer: customer,
        processor_id: "sub_#{SecureRandom.hex(8)}",
        processor_plan: :expiring_plan,
        status: "active",
        name: "default"
      )

      subscription.update!(status: "canceled", ends_at: 30.days.from_now)

      transaction = @user.credit_history.last
      assert_equal subscription.ends_at.to_i, transaction.expires_at.to_i
    end

    private

    def create_subscription(trial_ends_at: nil, plan: :test_plan)
      customer = create_customer
      customer.save!

      subscription = Pay::Subscription.new(
        customer: customer,
        processor_id: "sub_#{SecureRandom.hex(8)}",
        processor_plan: plan,
        trial_ends_at: trial_ends_at,
        status: trial_ends_at ? "trialing" : "incomplete",
        name: "default"
      )
      subscription.save!
      subscription
    end

    def create_customer
      Pay::Customer.new(
        owner: @user,
        processor: "stripe",
        processor_id: "cus_#{SecureRandom.hex(8)}"
      )
    end
  end
end
