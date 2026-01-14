# frozen_string_literal: true

require "test_helper"

class UsageCredits::CreditPackTest < ActiveSupport::TestCase
  setup do
    UsageCredits.reset!
  end

  teardown do
    UsageCredits.reset!
  end

  # ========================================
  # BASIC CREATION
  # ========================================

  test "creates credit pack with name" do
    pack = UsageCredits::CreditPack.new(:starter)
    assert_equal :starter, pack.name
  end

  test "creates credit pack with DSL block" do
    pack = UsageCredits::CreditPack.new(:starter)
    pack.instance_eval do
      gives 1000.credits
      costs 49.dollars
    end

    assert_equal 1000, pack.credits
    assert_equal 4900, pack.price_cents
  end

  test "default values are sensible" do
    pack = UsageCredits::CreditPack.new(:test)

    assert_equal 0, pack.credits
    assert_equal 0, pack.bonus_credits
    assert_equal 0, pack.price_cents
    assert_equal "USD", pack.price_currency
    assert_equal({}, pack.metadata)
  end

  # ========================================
  # DSL - CREDITS
  # ========================================

  test "gives sets base credits" do
    pack = UsageCredits::CreditPack.new(:test)
    pack.gives(500)

    assert_equal 500, pack.credits
  end

  test "gives accepts Cost::Fixed objects" do
    pack = UsageCredits::CreditPack.new(:test)
    pack.gives(750.credits)

    assert_equal 750, pack.credits
  end

  test "bonus adds bonus credits" do
    pack = UsageCredits::CreditPack.new(:test)
    pack.gives(1000)
    pack.bonus(200)

    assert_equal 1000, pack.credits
    assert_equal 200, pack.bonus_credits
  end

  test "total_credits includes both base and bonus" do
    pack = UsageCredits::CreditPack.new(:test)
    pack.gives(1000)
    pack.bonus(250)

    assert_equal 1250, pack.total_credits
  end

  # ========================================
  # DSL - PRICING
  # ========================================

  test "costs sets price in cents" do
    pack = UsageCredits::CreditPack.new(:test)
    pack.costs(4900)

    assert_equal 4900, pack.price_cents
  end

  test "cost alias works" do
    pack = UsageCredits::CreditPack.new(:test)
    pack.cost(2500)

    assert_equal 2500, pack.price_cents
  end

  test "dollars helper converts to cents" do
    pack = UsageCredits::CreditPack.new(:test)
    pack.costs(49.dollars)

    assert_equal 4900, pack.price_cents
  end

  test "price returns dollars as float" do
    pack = UsageCredits::CreditPack.new(:test)
    pack.costs(4999)

    assert_equal 49.99, pack.price
  end

  test "formatted_price shows price with currency" do
    pack = UsageCredits::CreditPack.new(:test)
    pack.costs(4900)

    assert_equal "49.00 USD", pack.formatted_price
  end

  # ========================================
  # DSL - CURRENCY
  # ========================================

  test "currency sets price currency" do
    pack = UsageCredits::CreditPack.new(:test)
    pack.currency(:eur)

    assert_equal "EUR", pack.price_currency
  end

  test "currency accepts string" do
    pack = UsageCredits::CreditPack.new(:test)
    pack.currency("gbp")

    assert_equal "GBP", pack.price_currency
  end

  test "currency rejects invalid currencies" do
    pack = UsageCredits::CreditPack.new(:test)

    assert_raises(ArgumentError) do
      pack.currency(:btc)
    end
  end

  test "valid currencies are accepted" do
    UsageCredits::Configuration::VALID_CURRENCIES.each do |currency|
      pack = UsageCredits::CreditPack.new(:test)
      pack.currency(currency)

      assert_equal currency.to_s.upcase, pack.price_currency
    end
  end

  # ========================================
  # DSL - METADATA
  # ========================================

  test "meta sets custom metadata" do
    pack = UsageCredits::CreditPack.new(:test)
    pack.meta(tier: "premium", popular: true)

    assert_equal "premium", pack.metadata[:tier]
    assert_equal true, pack.metadata[:popular]
  end

  test "meta merges with existing metadata" do
    pack = UsageCredits::CreditPack.new(:test)
    pack.meta(key1: "value1")
    pack.meta(key2: "value2")

    assert_equal "value1", pack.metadata[:key1]
    assert_equal "value2", pack.metadata[:key2]
  end

  # ========================================
  # VALIDATION
  # ========================================

  test "validate! passes for valid pack" do
    pack = UsageCredits::CreditPack.new(:starter)
    pack.gives(1000)
    pack.costs(4900)

    assert pack.validate!
  end

  test "validate! raises for blank name" do
    pack = UsageCredits::CreditPack.new("")

    error = assert_raises(ArgumentError) do
      pack.validate!
    end

    assert_includes error.message, "Name can't be blank"
  end

  test "validate! raises for zero credits" do
    pack = UsageCredits::CreditPack.new(:test)
    pack.costs(4900)

    error = assert_raises(ArgumentError) do
      pack.validate!
    end

    assert_includes error.message, "Credits must be greater than 0"
  end

  test "validate! raises for negative bonus credits" do
    pack = UsageCredits::CreditPack.new(:test)
    pack.gives(1000)
    pack.instance_variable_set(:@bonus_credits, -100)
    pack.costs(4900)

    error = assert_raises(ArgumentError) do
      pack.validate!
    end

    assert_includes error.message, "Bonus credits must be greater than or equal to 0"
  end

  test "validate! raises for zero price" do
    pack = UsageCredits::CreditPack.new(:test)
    pack.gives(1000)

    error = assert_raises(ArgumentError) do
      pack.validate!
    end

    assert_includes error.message, "Price must be greater than 0"
  end

  test "validate! raises for blank currency" do
    pack = UsageCredits::CreditPack.new(:test)
    pack.gives(1000)
    pack.costs(4900)
    pack.instance_variable_set(:@price_currency, "")

    error = assert_raises(ArgumentError) do
      pack.validate!
    end

    assert_includes error.message, "Currency can't be blank"
  end

  # ========================================
  # CALCULATIONS
  # ========================================

  test "credits_per_dollar calculates ratio" do
    pack = UsageCredits::CreditPack.new(:test)
    pack.gives(1000)
    pack.costs(50.dollars)  # 5000 cents = $50

    # 1000 credits / 50 dollars = 20 credits per dollar
    assert_equal 20.0, pack.credits_per_dollar
  end

  test "credits_per_dollar with bonus" do
    pack = UsageCredits::CreditPack.new(:test)
    pack.gives(1000)
    pack.bonus(200)
    pack.costs(60.dollars)  # 6000 cents = $60

    # 1200 total credits / 60 dollars = 20 credits per dollar
    assert_equal 20.0, pack.credits_per_dollar
  end

  test "credits_per_dollar returns zero when price is zero" do
    pack = UsageCredits::CreditPack.new(:test)
    pack.gives(1000)

    assert_equal 0, pack.credits_per_dollar
  end

  # ========================================
  # DISPLAY FORMATTING
  # ========================================

  test "display_credits shows base credits only" do
    pack = UsageCredits::CreditPack.new(:test)
    pack.gives(1000)

    assert_equal "1000 credits", pack.display_credits
  end

  test "display_credits shows bonus when present" do
    pack = UsageCredits::CreditPack.new(:test)
    pack.gives(1000)
    pack.bonus(200)

    assert_equal "1000 + 200 bonus credits", pack.display_credits
  end

  test "display_name returns titleized name" do
    pack = UsageCredits::CreditPack.new(:starter_pack)

    assert_equal "Starter Pack pack", pack.display_name
  end

  test "button_text generates purchase button text" do
    pack = UsageCredits::CreditPack.new(:test)
    pack.gives(1000)
    pack.costs(49.dollars)

    assert_equal "Get 1000 credits for 49.00 USD", pack.button_text
  end

  test "button_text includes bonus in text" do
    pack = UsageCredits::CreditPack.new(:test)
    pack.gives(1000)
    pack.bonus(200)
    pack.costs(49.dollars)

    assert_equal "Get 1000 + 200 bonus credits for 49.00 USD", pack.button_text
  end

  # ========================================
  # BASE METADATA
  # ========================================

  test "base_metadata includes essential pack info" do
    pack = UsageCredits::CreditPack.new(:starter)
    pack.gives(1000)
    pack.bonus(100)
    pack.costs(49.dollars)

    metadata = pack.base_metadata

    assert_equal "credit_pack", metadata[:purchase_type]
    assert_equal :starter, metadata[:pack_name]
    assert_equal 1000, metadata[:credits]
    assert_equal 100, metadata[:bonus_credits]
    assert_equal 4900, metadata[:price_cents]
    assert_equal "USD", metadata[:price_currency]
  end

  # ========================================
  # INTEGRATION WITH CONFIGURATION
  # ========================================

  test "pack registered via configuration DSL" do
    UsageCredits.configure do |config|
      config.credit_pack :test_pack do
        gives 500.credits
        costs 25.dollars
      end
    end

    pack = UsageCredits.find_pack(:test_pack)

    assert_not_nil pack
    assert_equal :test_pack, pack.name
    assert_equal 500, pack.credits
    assert_equal 2500, pack.price_cents
  end

  test "available_packs returns all registered packs" do
    UsageCredits.configure do |config|
      config.credit_pack :small do
        gives 100.credits
        costs 10.dollars
      end

      config.credit_pack :large do
        gives 1000.credits
        costs 80.dollars
      end
    end

    packs = UsageCredits.available_packs

    assert_equal 2, packs.size
    assert packs.any? { |p| p.name == :small }
    assert packs.any? { |p| p.name == :large }
  end

  # ========================================
  # EDGE CASES
  # ========================================

  test "handles very large credit amounts" do
    pack = UsageCredits::CreditPack.new(:enterprise)
    pack.gives(100_000_000)
    pack.costs(99999.dollars)

    assert_equal 100_000_000, pack.credits
    assert_equal 100_000_000, pack.total_credits
    assert pack.validate!
  end

  test "handles cents-only pricing" do
    pack = UsageCredits::CreditPack.new(:micro)
    pack.gives(10)
    pack.costs(99.cents)

    assert_equal 99, pack.price_cents
    assert_equal 0.99, pack.price
    assert pack.validate!
  end

  # ========================================
  # STRIPE CHECKOUT SESSION CREATION
  # ========================================

  test "create_checkout_session uses payment mode for one-time purchases" do
    pack = UsageCredits::CreditPack.new(:starter)
    pack.gives(1000)
    pack.costs(49.dollars)

    user = users(:rich_user)

    # Mock the payment processor to verify the arguments passed
    mock_payment_processor = Minitest::Mock.new
    mock_checkout_session = OpenStruct.new(url: "https://checkout.stripe.com/test")

    # Verify payment mode is used (not subscription mode)
    mock_payment_processor.expect(:checkout, mock_checkout_session) do |args|
      assert_equal "payment", args[:mode], "Credit packs should use payment mode"
      assert args[:line_items].present?, "line_items should be present"

      # Verify line items structure
      line_item = args[:line_items].first
      assert line_item[:price_data].present?, "price_data should be present for dynamic pricing"
      assert_equal "usd", line_item[:price_data][:currency]
      assert_equal 4900, line_item[:price_data][:unit_amount]
      assert_equal 1, line_item[:quantity]

      true
    end

    user.stub(:payment_processor, mock_payment_processor) do
      pack.create_checkout_session(user)
    end

    mock_payment_processor.verify
  end

  test "create_checkout_session passes payment_intent_data for payment mode" do
    pack = UsageCredits::CreditPack.new(:pro)
    pack.gives(5000)
    pack.costs(99.dollars)

    user = users(:rich_user)

    # Mock the payment processor to verify payment_intent_data is passed
    mock_payment_processor = Minitest::Mock.new
    mock_checkout_session = OpenStruct.new(url: "https://checkout.stripe.com/test")

    # For payment mode, payment_intent_data IS allowed and should be present
    mock_payment_processor.expect(:checkout, mock_checkout_session) do |args|
      assert_equal "payment", args[:mode]

      # payment_intent_data is VALID for payment mode (unlike subscription mode)
      assert args.key?(:payment_intent_data), "payment_intent_data should be present for payment mode"
      assert args[:payment_intent_data][:metadata].present?, "payment_intent_data metadata should be present"

      # Verify metadata contains pack info
      metadata = args[:payment_intent_data][:metadata]
      assert_equal "credit_pack", metadata[:purchase_type]
      assert_equal :pro, metadata[:pack_name]
      assert_equal 5000, metadata[:credits]

      true
    end

    user.stub(:payment_processor, mock_payment_processor) do
      pack.create_checkout_session(user)
    end

    mock_payment_processor.verify
  end

  test "create_checkout_session includes all pack configuration in metadata" do
    pack = UsageCredits::CreditPack.new(:enterprise)
    pack.gives(10_000)
    pack.bonus(2_000)
    pack.costs(199.dollars)

    user = users(:rich_user)

    mock_payment_processor = Minitest::Mock.new
    mock_checkout_session = OpenStruct.new(url: "https://checkout.stripe.com/test")

    mock_payment_processor.expect(:checkout, mock_checkout_session) do |args|
      metadata = args[:payment_intent_data][:metadata]

      # Verify all pack configuration is included
      assert_equal "credit_pack", metadata[:purchase_type]
      assert_equal :enterprise, metadata[:pack_name]
      assert_equal 10_000, metadata[:credits]
      assert_equal 2_000, metadata[:bonus_credits]
      assert_equal 19900, metadata[:price_cents]
      assert_equal "USD", metadata[:price_currency]

      # Also verify session-level metadata
      assert_equal metadata, args[:metadata], "Session metadata should match payment_intent_data metadata"

      true
    end

    user.stub(:payment_processor, mock_payment_processor) do
      pack.create_checkout_session(user)
    end

    mock_payment_processor.verify
  end

  test "create_checkout_session raises when user has no payment processor" do
    pack = UsageCredits::CreditPack.new(:test)
    pack.gives(100)
    pack.costs(10.dollars)

    user_without_payment = Object.new

    error = assert_raises(ArgumentError) do
      pack.create_checkout_session(user_without_payment)
    end

    assert_includes error.message, "must have a payment processor"
  end

  test "create_checkout_session includes product name and description" do
    pack = UsageCredits::CreditPack.new(:starter)
    pack.gives(1000)
    pack.costs(49.dollars)

    user = users(:rich_user)

    mock_payment_processor = Minitest::Mock.new
    mock_checkout_session = OpenStruct.new(url: "https://checkout.stripe.com/test")

    mock_payment_processor.expect(:checkout, mock_checkout_session) do |args|
      product_data = args[:line_items].first[:price_data][:product_data]

      assert_equal "Starter pack", product_data[:name]
      assert_equal "1000 credits", product_data[:description]

      true
    end

    user.stub(:payment_processor, mock_payment_processor) do
      pack.create_checkout_session(user)
    end

    mock_payment_processor.verify
  end

  # ========================================
  # CUSTOM CHECKOUT OPTIONS
  # ========================================

  test "create_checkout_session passes through success_url and cancel_url" do
    pack = UsageCredits::CreditPack.new(:starter)
    pack.gives(1000)
    pack.costs(49.dollars)

    user = users(:rich_user)

    mock_payment_processor = Minitest::Mock.new
    mock_checkout_session = OpenStruct.new(url: "https://checkout.stripe.com/test")

    mock_payment_processor.expect(:checkout, mock_checkout_session) do |args|
      assert_equal "https://example.com/success", args[:success_url]
      assert_equal "https://example.com/cancel", args[:cancel_url]
      true
    end

    user.stub(:payment_processor, mock_payment_processor) do
      pack.create_checkout_session(user,
        success_url: "https://example.com/success",
        cancel_url: "https://example.com/cancel"
      )
    end

    mock_payment_processor.verify
  end

  test "create_checkout_session passes through allow_promotion_codes" do
    pack = UsageCredits::CreditPack.new(:starter)
    pack.gives(1000)
    pack.costs(49.dollars)

    user = users(:rich_user)

    mock_payment_processor = Minitest::Mock.new
    mock_checkout_session = OpenStruct.new(url: "https://checkout.stripe.com/test")

    mock_payment_processor.expect(:checkout, mock_checkout_session) do |args|
      assert_equal true, args[:allow_promotion_codes]
      true
    end

    user.stub(:payment_processor, mock_payment_processor) do
      pack.create_checkout_session(user, allow_promotion_codes: true)
    end

    mock_payment_processor.verify
  end

  test "create_checkout_session passes through locale" do
    pack = UsageCredits::CreditPack.new(:starter)
    pack.gives(1000)
    pack.costs(49.dollars)

    user = users(:rich_user)

    mock_payment_processor = Minitest::Mock.new
    mock_checkout_session = OpenStruct.new(url: "https://checkout.stripe.com/test")

    mock_payment_processor.expect(:checkout, mock_checkout_session) do |args|
      assert_equal "es", args[:locale]
      true
    end

    user.stub(:payment_processor, mock_payment_processor) do
      pack.create_checkout_session(user, locale: "es")
    end

    mock_payment_processor.verify
  end

  test "create_checkout_session passes through customer_email" do
    pack = UsageCredits::CreditPack.new(:starter)
    pack.gives(1000)
    pack.costs(49.dollars)

    user = users(:rich_user)

    mock_payment_processor = Minitest::Mock.new
    mock_checkout_session = OpenStruct.new(url: "https://checkout.stripe.com/test")

    mock_payment_processor.expect(:checkout, mock_checkout_session) do |args|
      assert_equal "customer@example.com", args[:customer_email]
      true
    end

    user.stub(:payment_processor, mock_payment_processor) do
      pack.create_checkout_session(user, customer_email: "customer@example.com")
    end

    mock_payment_processor.verify
  end

  test "create_checkout_session passes through multiple options at once" do
    pack = UsageCredits::CreditPack.new(:starter)
    pack.gives(1000)
    pack.costs(49.dollars)

    user = users(:rich_user)

    mock_payment_processor = Minitest::Mock.new
    mock_checkout_session = OpenStruct.new(url: "https://checkout.stripe.com/test")

    mock_payment_processor.expect(:checkout, mock_checkout_session) do |args|
      assert_equal "https://example.com/success", args[:success_url]
      assert_equal "https://example.com/cancel", args[:cancel_url]
      assert_equal true, args[:allow_promotion_codes]
      assert_equal "fr", args[:locale]
      assert_equal "required", args[:billing_address_collection]
      true
    end

    user.stub(:payment_processor, mock_payment_processor) do
      pack.create_checkout_session(user,
        success_url: "https://example.com/success",
        cancel_url: "https://example.com/cancel",
        allow_promotion_codes: true,
        locale: "fr",
        billing_address_collection: "required"
      )
    end

    mock_payment_processor.verify
  end

  # ========================================
  # METADATA MERGING (CRITICAL FOR FULFILLMENT)
  # ========================================

  test "create_checkout_session merges custom metadata with base_metadata" do
    pack = UsageCredits::CreditPack.new(:starter)
    pack.gives(1000)
    pack.costs(49.dollars)

    user = users(:rich_user)

    mock_payment_processor = Minitest::Mock.new
    mock_checkout_session = OpenStruct.new(url: "https://checkout.stripe.com/test")

    mock_payment_processor.expect(:checkout, mock_checkout_session) do |args|
      metadata = args[:metadata]

      # Custom metadata should be present
      assert_equal "custom_value", metadata[:custom_key]
      assert_equal "org_123", metadata[:organization_id]

      # Base metadata must still be present (critical for fulfillment)
      assert_equal "credit_pack", metadata[:purchase_type]
      assert_equal :starter, metadata[:pack_name]
      assert_equal 1000, metadata[:credits]
      assert_equal 0, metadata[:bonus_credits]
      assert_equal 4900, metadata[:price_cents]
      assert_equal "USD", metadata[:price_currency]

      true
    end

    user.stub(:payment_processor, mock_payment_processor) do
      pack.create_checkout_session(user,
        metadata: { custom_key: "custom_value", organization_id: "org_123" }
      )
    end

    mock_payment_processor.verify
  end

  test "create_checkout_session base_metadata takes precedence over custom metadata for critical fields" do
    pack = UsageCredits::CreditPack.new(:starter)
    pack.gives(1000)
    pack.costs(49.dollars)

    user = users(:rich_user)

    mock_payment_processor = Minitest::Mock.new
    mock_checkout_session = OpenStruct.new(url: "https://checkout.stripe.com/test")

    mock_payment_processor.expect(:checkout, mock_checkout_session) do |args|
      metadata = args[:metadata]

      # Attempting to override critical fields should fail - base_metadata wins
      assert_equal "credit_pack", metadata[:purchase_type], "purchase_type should not be overridable"
      assert_equal :starter, metadata[:pack_name], "pack_name should not be overridable"
      assert_equal 1000, metadata[:credits], "credits should not be overridable"

      true
    end

    user.stub(:payment_processor, mock_payment_processor) do
      # Try to override critical metadata fields (malicious or accidental)
      pack.create_checkout_session(user,
        metadata: {
          purchase_type: "something_else",
          pack_name: "hacked",
          credits: 999999
        }
      )
    end

    mock_payment_processor.verify
  end

  test "create_checkout_session merges payment_intent_data metadata correctly" do
    pack = UsageCredits::CreditPack.new(:pro)
    pack.gives(5000)
    pack.bonus(500)
    pack.costs(99.dollars)

    user = users(:rich_user)

    mock_payment_processor = Minitest::Mock.new
    mock_checkout_session = OpenStruct.new(url: "https://checkout.stripe.com/test")

    mock_payment_processor.expect(:checkout, mock_checkout_session) do |args|
      pi_metadata = args[:payment_intent_data][:metadata]

      # Custom metadata should be present
      assert_equal "ref_123", pi_metadata[:internal_ref]

      # Base metadata must still be present
      assert_equal "credit_pack", pi_metadata[:purchase_type]
      assert_equal :pro, pi_metadata[:pack_name]
      assert_equal 5000, pi_metadata[:credits]
      assert_equal 500, pi_metadata[:bonus_credits]

      true
    end

    user.stub(:payment_processor, mock_payment_processor) do
      pack.create_checkout_session(user,
        payment_intent_data: { metadata: { internal_ref: "ref_123" } }
      )
    end

    mock_payment_processor.verify
  end

  test "create_checkout_session passes through other payment_intent_data options" do
    pack = UsageCredits::CreditPack.new(:starter)
    pack.gives(1000)
    pack.costs(49.dollars)

    user = users(:rich_user)

    mock_payment_processor = Minitest::Mock.new
    mock_checkout_session = OpenStruct.new(url: "https://checkout.stripe.com/test")

    mock_payment_processor.expect(:checkout, mock_checkout_session) do |args|
      pi_data = args[:payment_intent_data]

      # Other payment_intent_data options should pass through
      assert_equal "customer@example.com", pi_data[:receipt_email]
      assert_equal "Thank you!", pi_data[:description]

      # Metadata should still have base fields
      assert_equal "credit_pack", pi_data[:metadata][:purchase_type]

      true
    end

    user.stub(:payment_processor, mock_payment_processor) do
      pack.create_checkout_session(user,
        payment_intent_data: {
          receipt_email: "customer@example.com",
          description: "Thank you!"
        }
      )
    end

    mock_payment_processor.verify
  end

  # ========================================
  # PROTECTED PARAMETERS (SECURITY)
  # ========================================

  test "create_checkout_session cannot override mode parameter" do
    pack = UsageCredits::CreditPack.new(:starter)
    pack.gives(1000)
    pack.costs(49.dollars)

    user = users(:rich_user)

    mock_payment_processor = Minitest::Mock.new
    mock_checkout_session = OpenStruct.new(url: "https://checkout.stripe.com/test")

    mock_payment_processor.expect(:checkout, mock_checkout_session) do |args|
      # Mode must always be "payment" for credit packs, not "subscription"
      assert_equal "payment", args[:mode], "mode parameter should not be overridable"
      true
    end

    user.stub(:payment_processor, mock_payment_processor) do
      # Try to override mode (should be ignored)
      pack.create_checkout_session(user, mode: "subscription")
    end

    mock_payment_processor.verify
  end

  test "create_checkout_session cannot override line_items parameter" do
    pack = UsageCredits::CreditPack.new(:starter)
    pack.gives(1000)
    pack.costs(49.dollars)

    user = users(:rich_user)

    mock_payment_processor = Minitest::Mock.new
    mock_checkout_session = OpenStruct.new(url: "https://checkout.stripe.com/test")

    mock_payment_processor.expect(:checkout, mock_checkout_session) do |args|
      # line_items should be the pack's configured items, not the malicious ones
      line_item = args[:line_items].first
      assert_equal 4900, line_item[:price_data][:unit_amount], "line_items should not be overridable"
      assert_equal 1, line_item[:quantity]
      true
    end

    user.stub(:payment_processor, mock_payment_processor) do
      # Try to override line_items (should be ignored)
      pack.create_checkout_session(user,
        line_items: [{ price: "price_malicious", quantity: 1 }]
      )
    end

    mock_payment_processor.verify
  end

  # ========================================
  # BACKWARD COMPATIBILITY
  # ========================================

  test "create_checkout_session works without any options (backward compatible)" do
    pack = UsageCredits::CreditPack.new(:starter)
    pack.gives(1000)
    pack.costs(49.dollars)

    user = users(:rich_user)

    mock_payment_processor = Minitest::Mock.new
    mock_checkout_session = OpenStruct.new(url: "https://checkout.stripe.com/test")

    mock_payment_processor.expect(:checkout, mock_checkout_session) do |args|
      assert_equal "payment", args[:mode]
      assert args[:line_items].present?
      assert args[:metadata].present?
      assert args[:payment_intent_data].present?
      true
    end

    user.stub(:payment_processor, mock_payment_processor) do
      # Call without any options - should work exactly as before
      pack.create_checkout_session(user)
    end

    mock_payment_processor.verify
  end

  # ========================================
  # EDGE CASES
  # ========================================

  test "create_checkout_session handles empty options hash" do
    pack = UsageCredits::CreditPack.new(:starter)
    pack.gives(1000)
    pack.costs(49.dollars)

    user = users(:rich_user)

    mock_payment_processor = Minitest::Mock.new
    mock_checkout_session = OpenStruct.new(url: "https://checkout.stripe.com/test")

    mock_payment_processor.expect(:checkout, mock_checkout_session) do |args|
      assert_equal "payment", args[:mode]
      assert_equal "credit_pack", args[:metadata][:purchase_type]
      true
    end

    user.stub(:payment_processor, mock_payment_processor) do
      pack.create_checkout_session(user, **{})
    end

    mock_payment_processor.verify
  end

  test "create_checkout_session handles nil metadata gracefully" do
    pack = UsageCredits::CreditPack.new(:starter)
    pack.gives(1000)
    pack.costs(49.dollars)

    user = users(:rich_user)

    mock_payment_processor = Minitest::Mock.new
    mock_checkout_session = OpenStruct.new(url: "https://checkout.stripe.com/test")

    mock_payment_processor.expect(:checkout, mock_checkout_session) do |args|
      # Base metadata should still be present
      assert_equal "credit_pack", args[:metadata][:purchase_type]
      true
    end

    user.stub(:payment_processor, mock_payment_processor) do
      pack.create_checkout_session(user, metadata: nil)
    end

    mock_payment_processor.verify
  end

  test "create_checkout_session handles nil payment_intent_data gracefully" do
    pack = UsageCredits::CreditPack.new(:starter)
    pack.gives(1000)
    pack.costs(49.dollars)

    user = users(:rich_user)

    mock_payment_processor = Minitest::Mock.new
    mock_checkout_session = OpenStruct.new(url: "https://checkout.stripe.com/test")

    mock_payment_processor.expect(:checkout, mock_checkout_session) do |args|
      # Base metadata should still be present in payment_intent_data
      assert_equal "credit_pack", args[:payment_intent_data][:metadata][:purchase_type]
      true
    end

    user.stub(:payment_processor, mock_payment_processor) do
      pack.create_checkout_session(user, payment_intent_data: nil)
    end

    mock_payment_processor.verify
  end

  # ========================================
  # NON-MUTATION OF CALLER'S DATA
  # ========================================

  test "create_checkout_session does not mutate caller's payment_intent_data hash" do
    pack = UsageCredits::CreditPack.new(:starter)
    pack.gives(1000)
    pack.costs(49.dollars)

    user = users(:rich_user)

    mock_payment_processor = Minitest::Mock.new
    mock_checkout_session = OpenStruct.new(url: "https://checkout.stripe.com/test")

    mock_payment_processor.expect(:checkout, mock_checkout_session) { true }

    # Create a hash that the caller might want to reuse
    caller_payment_intent_data = {
      receipt_email: "customer@example.com",
      metadata: { internal_ref: "ref_123", tracking_id: "track_456" }
    }

    # Store the original state for comparison
    original_metadata = caller_payment_intent_data[:metadata].dup

    user.stub(:payment_processor, mock_payment_processor) do
      pack.create_checkout_session(user, payment_intent_data: caller_payment_intent_data)
    end

    # The caller's hash should NOT have been mutated
    assert_equal original_metadata, caller_payment_intent_data[:metadata],
      "The caller's payment_intent_data[:metadata] should not be deleted or modified"
    assert_equal "customer@example.com", caller_payment_intent_data[:receipt_email],
      "Other keys in payment_intent_data should remain intact"

    mock_payment_processor.verify
  end

  test "create_checkout_session allows reusing payment_intent_data hash for multiple calls" do
    pack = UsageCredits::CreditPack.new(:starter)
    pack.gives(1000)
    pack.costs(49.dollars)

    user = users(:rich_user)

    # A reusable hash that a caller might use for multiple checkout sessions
    reusable_options = {
      receipt_email: "customer@example.com",
      metadata: { campaign: "summer_sale" }
    }

    mock_payment_processor = Minitest::Mock.new
    mock_checkout_session = OpenStruct.new(url: "https://checkout.stripe.com/test")

    # Expect two calls
    mock_payment_processor.expect(:checkout, mock_checkout_session) { true }
    mock_payment_processor.expect(:checkout, mock_checkout_session) { true }

    user.stub(:payment_processor, mock_payment_processor) do
      # First call
      pack.create_checkout_session(user, payment_intent_data: reusable_options)

      # Second call should work identically (hash not mutated)
      pack.create_checkout_session(user, payment_intent_data: reusable_options)
    end

    # The hash should still have its metadata after both calls
    assert_equal({ campaign: "summer_sale" }, reusable_options[:metadata],
      "Metadata should still be present after multiple checkout calls")

    mock_payment_processor.verify
  end
end
