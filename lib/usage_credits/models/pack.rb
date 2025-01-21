# frozen_string_literal: true

module UsageCredits
  # Defines credit packs that can be purchased
  class Pack
    attr_reader :name, :credits, :bonus_credits, :price_cents, :price_currency, :metadata

    def initialize(name:, credits:, bonus_credits: 0, price_cents:, price_currency: nil, metadata: {})
      @name = name
      @credits = credits
      @bonus_credits = bonus_credits
      @price_cents = price_cents
      price_currency = price_currency || UsageCredits.configuration.default_currency
      price_currency = price_currency.to_s.downcase.to_sym
      unless UsageCredits::Configuration::VALID_CURRENCIES.include?(price_currency)
        raise ArgumentError, "Invalid currency. Must be one of: #{UsageCredits::Configuration::VALID_CURRENCIES.join(', ')}"
      end
      @price_currency = price_currency.to_s.upcase
      @metadata = metadata.transform_keys(&:to_sym)

      validate!
    end

    def validate!
      raise ArgumentError, "Name can't be blank" if name.blank?
      raise ArgumentError, "Credits must be greater than 0" unless credits.to_i.positive?
      raise ArgumentError, "Bonus credits must be greater than or equal to 0" if bonus_credits.to_i.negative?
      raise ArgumentError, "Price must be greater than 0" unless price_cents.to_i.positive?
      raise ArgumentError, "Currency can't be blank" if price_currency.blank?
      raise ArgumentError, "Price must be in whole cents ($49 = 4900)" if price_cents % 100 != 0
    end

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

      # More intuitive currency setting
      def currency(currency)
        currency = currency.to_s.downcase.to_sym
        unless UsageCredits::Configuration::VALID_CURRENCIES.include?(currency)
          raise ArgumentError, "Invalid currency. Must be one of: #{UsageCredits::Configuration::VALID_CURRENCIES}"
        end
        @price_currency = currency.to_s.upcase
      end

      # Add metadata
      def meta(hash)
        @metadata.merge!(hash.transform_keys(&:to_s))
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

    # Override metadata getter to support both string and symbol keys
    def metadata
      @indifferent_metadata ||= ActiveSupport::HashWithIndifferentAccess.new(@metadata)
    end

    # Override metadata setter to ensure consistent storage
    def metadata=(hash)
      @indifferent_metadata = nil  # Clear cache
      @metadata = hash.transform_keys(&:to_sym)
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

    def display_credits
      if bonus_credits.positive?
        "#{credits} + #{bonus_credits} bonus credits"
      else
        "#{credits} credits"
      end
    end

    def display_name
      "#{display_credits} pack"
    end

    def display_description
      display_credits
    end

    # Generate human-friendly button text for purchase links
    def button_text
      "Get #{display_credits} for #{formatted_price}"
    end

    # Apply the pack to a wallet
    def fulfill_purchase(user)
      user.credit_wallet.add_credits(
        total_credits,
        metadata: base_metadata.merge(
          purchased_at: Time.current,
          **metadata
        ),
        category: :credit_pack_purchase
      )
    end

    # Create a Stripe Checkout session for this pack
    def create_checkout_session(user)
      raise ArgumentError, "User must have a payment processor" unless user.respond_to?(:payment_processor) && user.payment_processor

      user.payment_processor.checkout(
        mode: "payment",
        line_items: [{
          price_data: {
            currency: price_currency.downcase,
            unit_amount: price_cents,
            product_data: {
              name: display_name,
              description: display_description
            }
          },
          quantity: 1
        }],
        payment_intent_data: {
          metadata: base_metadata
        },
        metadata: base_metadata
      )
    end

    def base_metadata
      {
        purchase_type: "credit_pack",
        pack_name: name,
        price_cents: price_cents,
        price_currency: price_currency,
        credits: credits,
        bonus_credits: bonus_credits
      }
    end

  end
end
