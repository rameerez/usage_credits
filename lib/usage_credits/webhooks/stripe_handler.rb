# frozen_string_literal: true

module UsageCredits
  module Webhooks
    # Handles Stripe webhook events for credit management
    class StripeHandler
      class << self
        def handle_checkout_completed(event)
          object = event.data.object
          return unless object.metadata["credit_pack"]

          # Find the user from the customer ID
          pay_customer = Pay::Customer.find_by(processor: :stripe, processor_id: object.customer)
          return unless pay_customer

          # Find the credit pack
          pack = UsageCredits.packs[object.metadata["credit_pack"]]
          return unless pack

          # Add credits to the user's wallet
          pack.apply_to_wallet(
            pay_customer.owner.credit_wallet,
            source: Pay::Charge.find_by(processor_id: object.payment_intent)
          )
        end

        def handle_subscription_created(event)
          object = event.data.object
          subscription = Pay::Subscription.find_by(processor: :stripe, processor_id: object.id)
          return unless subscription

          rule = UsageCredits.subscription_rules[subscription.processor_plan]
          return unless rule

          rule.apply_to_subscription(subscription)
        end

        def handle_subscription_updated(event)
          object = event.data.object
          subscription = Pay::Subscription.find_by(processor: :stripe, processor_id: object.id)
          return unless subscription

          rule = UsageCredits.subscription_rules[subscription.processor_plan]
          return unless rule

          # Handle plan changes
          if object.metadata["previous_plan"] && object.metadata["previous_plan"] != subscription.processor_plan
            handle_plan_change(subscription, object.metadata["previous_plan"], rule)
          end

          # Handle subscription status changes
          case object.status
          when "active"
            handle_subscription_activated(subscription, rule)
          when "past_due"
            handle_subscription_past_due(subscription)
          when "canceled"
            handle_subscription_canceled(subscription)
          end
        end

        def handle_subscription_deleted(event)
          object = event.data.object
          subscription = Pay::Subscription.find_by(processor: :stripe, processor_id: object.id)
          return unless subscription

          rule = UsageCredits.subscription_rules[subscription.processor_plan]
          return unless rule

          handle_subscription_canceled(subscription) if rule.expire_credits_on_cancel
        end

        private

        def handle_plan_change(subscription, previous_plan, new_rule)
          wallet = subscription.customer.owner.credit_wallet
          old_rule = UsageCredits.subscription_rules[previous_plan]

          # Handle credit adjustments for plan changes
          if old_rule && new_rule
            handle_credit_adjustment(wallet, old_rule, new_rule)
          end
        end

        def handle_credit_adjustment(wallet, old_rule, new_rule)
          # Implement credit adjustment logic for plan changes
          # This could involve prorating credits, adding/removing credits, etc.
        end

        def handle_subscription_activated(subscription, rule)
          return unless rule.monthly_credits.positive?

          # Add monthly credits if subscription was reactivated
          rule.apply_to_subscription(subscription)
        end

        def handle_subscription_past_due(subscription)
          # Optionally freeze credits or take other actions
        end

        def handle_subscription_canceled(subscription)
          wallet = subscription.customer.owner.credit_wallet
          rule = UsageCredits.subscription_rules[subscription.processor_plan]

          return unless rule&.expire_credits_on_cancel

          # Schedule credit expiration if configured
          if rule.credit_expiration_period
            wallet.update!(credits_expire_at: Time.current + rule.credit_expiration_period)
          end
        end
      end
    end
  end
end
