# frozen_string_literal: true

module UsageCredits
  # A DSL to define credit packs that users can buy as one-time purchases.
  #
  # Credit packs can be purchased independently and separately from any subscription.
  #
  # The actual credit fulfillment is handled by the PayChargeExtension.
  #
  # @see PayChargeExtension for the actual payment processing, credit pack fulfilling and refund handling
  class CreditPack

    attr_reader :name,
                :credits, :bonus_credits,
                :price_cents, :price_currency,
                :metadata

    def initialize(name)
      @name = name
      @credits = 0
      @bonus_credits = 0
      @price_cents = 0
      @price_currency = UsageCredits.configuration.default_currency.to_s.upcase
      @metadata = {}
    end

    # =========================================
    # DSL Methods (used in initializer blocks)
    # =========================================

    # Set the base number of credits
    def gives(amount)
      @credits = amount.to_i
    end

    # Set bonus credits (e.g., for promotions)
    def bonus(amount)
      @bonus_credits = amount.to_i
    end

    # Set the price in cents (e.g., 4900 for $49.00)
    def costs(cents)
      @price_cents = cents
    end
    alias_method :cost, :costs

    # Set the currency (defaults to configuration)
    def currency(currency)
      currency = currency.to_s.downcase.to_sym
      unless UsageCredits::Configuration::VALID_CURRENCIES.include?(currency)
        raise ArgumentError, "Invalid currency. Must be one of: #{UsageCredits::Configuration::VALID_CURRENCIES.join(', ')}"
      end
      @price_currency = currency.to_s.upcase
    end

    # Add custom metadata
    def meta(hash)
      @metadata.merge!(hash.transform_keys(&:to_sym))
    end

    # =========================================
    # Validation
    # =========================================

    def validate!
      raise ArgumentError, "Name can't be blank" if name.blank?
      raise ArgumentError, "Credits must be greater than 0" unless credits.to_i.positive?
      raise ArgumentError, "Bonus credits must be greater than or equal to 0" if bonus_credits.to_i.negative?
      raise ArgumentError, "Price must be greater than 0" unless price_cents.to_i.positive?
      raise ArgumentError, "Currency can't be blank" if price_currency.blank?
      # raise ArgumentError, "Price must be in whole cents ($49 = 4900)" if price_cents % 100 != 0 # Payment processors should handle this anyways
      true
    end

    # =========================================
    # Credit & Price Calculations
    # =========================================

    # Get total credits (including bonus)
    def total_credits
      credits + bonus_credits
    end

    # Get price in dollars
    def price
      price_cents / 100.0
    end

    # Get formatted price (e.g., "49.00 USD")
    def formatted_price
      format("%.2f %s", price, price_currency)
    end

    # Get credits per dollar ratio (for comparison)
    def credits_per_dollar
      return 0 if price.zero?
      total_credits / price
    end

    # =========================================
    # Display Formatting
    # =========================================

    def display_credits
      if bonus_credits.positive?
        "#{credits} + #{bonus_credits} bonus credits"
      else
        "#{credits} credits"
      end
    end
    alias_method :display_description, :display_credits

    def display_name
      "#{name.to_s.titleize} pack"
    end

    # Generate human-friendly button text for purchase links
    def button_text
      "Get #{display_credits} for #{formatted_price}"
    end

    # =========================================
    # Payment Integration
    # =========================================

    # Create a Stripe Checkout session for this pack.
    #
    # Accepts optional checkout options that are passed through to the payment processor.
    # Common options include:
    #   - success_url: URL to redirect after successful payment
    #   - cancel_url: URL to redirect if customer cancels
    #   - allow_promotion_codes: Enable promotion code input (true/false)
    #   - locale: Checkout page locale (e.g., "en", "es", "fr")
    #   - customer_email: Pre-fill the customer's email
    #
    # Note: The following parameters are protected and cannot be overridden:
    #   - mode: Always "payment" for credit packs
    #   - line_items: Always the configured credit pack
    #
    # Custom metadata passed in options will be merged with (not replace) the
    # base pack metadata required for credit fulfillment.
    #
    # @param user [Object] A user with a payment processor (via Pay gem)
    # @param options [Hash] Additional checkout options passed to the payment processor
    # @return [Object] The checkout session object
    #
    # @example Basic usage
    #   pack.create_checkout_session(current_user)
    #
    # @example With custom options
    #   pack.create_checkout_session(current_user,
    #     success_url: credits_url,
    #     cancel_url: pricing_url,
    #     allow_promotion_codes: true
    #   )
    #
    def create_checkout_session(user, **options)
      raise ArgumentError, "User must have a payment processor" unless user.respond_to?(:payment_processor) && user.payment_processor

      # Merge custom metadata with base_metadata (base_metadata takes precedence for critical fields)
      custom_metadata = options.delete(:metadata) || {}
      merged_metadata = custom_metadata.merge(base_metadata)

      # Handle payment_intent_data specially to preserve metadata
      # We dup to avoid mutating the caller's original hash
      custom_payment_intent_data = (options.delete(:payment_intent_data) || {}).dup
      custom_pi_metadata = custom_payment_intent_data.delete(:metadata) || {}
      merged_payment_intent_data = custom_payment_intent_data.merge(
        metadata: custom_pi_metadata.merge(base_metadata)
      )

      # Remove protected parameters that could break credit fulfillment
      options.delete(:mode)
      options.delete(:line_items)

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
        payment_intent_data: merged_payment_intent_data,
        metadata: merged_metadata,
        **options
      )
    end

    def base_metadata
      {
        purchase_type: "credit_pack",
        pack_name: name,
        credits: credits,
        bonus_credits: bonus_credits,
        price_cents: price_cents,
        price_currency: price_currency
      }
    end
  end
end
