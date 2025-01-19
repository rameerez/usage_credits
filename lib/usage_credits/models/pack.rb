# frozen_string_literal: true

module UsageCredits
  # Defines credit packs that can be purchased
  class Pack < ApplicationRecord
    self.table_name = "usage_credits_packs"

    validates :name, presence: true, uniqueness: true
    validates :credits, presence: true, numericality: { greater_than: 0 }
    validates :bonus_credits, numericality: { greater_than_or_equal_to: 0 }
    validates :price_cents, presence: true, numericality: { greater_than: 0 }
    validates :price_currency, presence: true

    # DSL methods for pack definition
    class Builder
      attr_reader :name, :credits_amount, :bonus_amount, :price_cents, :price_currency, :metadata

      def initialize(name)
        @name = name
        @credits_amount = 0
        @bonus_amount = 0
        @price_cents = 0
        @price_currency = UsageCredits.configuration.default_currency.to_s.upcase
        @metadata = {}
      end

      # More intuitive credit amount setting
      def includes(amount)
        @credits_amount = amount.to_i
      end

      # More intuitive bonus credit setting
      def bonus(amount)
        @bonus_amount = amount.to_i
      end

      # More intuitive price setting
      def costs(cents)
        @price_cents = cents
      end

      # Add metadata
      def meta(hash)
        @metadata.merge!(hash)
      end

      # Build the pack
      def build
        Pack.new(
          name: name,
          credits: credits_amount,
          bonus_credits: bonus_amount,
          price_cents: price_cents,
          price_currency: price_currency,
          metadata: metadata
        )
      end
    end

    # Get total credits (including bonus)
    def total_credits
      credits + bonus_credits
    end

    # Get price in dollars
    def price
      price_cents / 100.0
    end

    # Get formatted price
    def formatted_price
      format("%.2f %s", price, price_currency)
    end

    # Get credits per dollar ratio
    def credits_per_dollar
      return 0 if price.zero?

      total_credits / price
    end

    # Apply the pack to a wallet
    def apply_to_wallet(wallet, source: nil)
      wallet.add_credits(
        total_credits,
        metadata: {
          pack_name: name,
          price_cents: price_cents,
          price_currency: price_currency,
          credits: credits,
          bonus_credits: bonus_credits
        },
        category: :credit_pack_purchase,
        source: source
      )
    end

    # Create a Stripe Checkout session for this pack
    def create_checkout_session(user)
      user.payment_processor.checkout(
        mode: "payment",
        line_items: [{
          price_data: {
            currency: price_currency.downcase,
            unit_amount: price_cents,
            product_data: {
              name: "#{credits} Credits Pack",
              description: bonus_credits.positive? ? "Includes #{bonus_credits} bonus credits!" : nil
            }
          },
          quantity: 1
        }],
        metadata: {
          credit_pack: name,
          credits: credits,
          bonus_credits: bonus_credits
        }
      )
    end
  end
end
