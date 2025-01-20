# frozen_string_literal: true

require "test_helper"

module UsageCredits
  class CreditPackTest < ActiveSupport::TestCase
    setup do
      @user = users(:default)
      @wallet = @user.credit_wallet

      # Define test credit packs
      UsageCredits.configure do |config|
        config.credit_pack :starter do
          includes 1000.credits
          costs 49.dollars
        end

        config.credit_pack :pro do
          includes 5000.credits
          costs 199.dollars
        end
      end
    end

    teardown do
      # Reset the entire configuration to defaults
      UsageCredits.configuration = UsageCredits::Configuration.new
    end

    test "credit packs are defined in configuration" do
      packs = UsageCredits.configuration.credit_packs
      assert_includes packs.keys, :starter
      assert_includes packs.keys, :pro
    end

    test "credit packs have correct attributes" do
      packs = UsageCredits.configuration.credit_packs
      starter = packs[:starter]
      assert_equal 1000, starter.credits
      assert_equal 4900, starter.price_cents # 49 dollars in cents

      pro = packs[:pro]
      assert_equal 5000, pro.credits
      assert_equal 19900, pro.price_cents
    end

    test "credit pack prices must be in whole dollars" do
      assert_raises(ArgumentError) do
        UsageCredits.configure do |config|
          config.credit_pack :invalid do
            includes 1000.credits
            costs 49.50.dollars
          end
        end
      end
    end

    test "credit pack amounts must be whole numbers" do
      assert_raises(ArgumentError) do
        UsageCredits.configure do |config|
          config.credit_pack :invalid do
            includes 100.5.credits
            costs 49.dollars
          end
        end
      end
    end

    test "can create checkout session for credit pack" do
      packs = UsageCredits.configuration.credit_packs
      pack = packs[:starter]
      customer = create_customer

      session = pack.create_checkout_session(@user)
      assert_not_nil session
      assert_not_nil session.url
    end

    test "credits are given after successful purchase" do
      packs = UsageCredits.configuration.credit_packs
      pack = packs[:starter]
      customer = create_customer

      pack.fulfill_purchase(@user)
      assert_equal 1000, @user.credits

      transaction = @user.credit_history.last
      assert_equal "credit_pack_purchase", transaction.category
      assert_equal "starter", transaction.metadata["pack"]
      assert_equal 1000, transaction.amount
      assert_equal 4900, transaction.metadata["price_cents"]
    end

    test "can purchase multiple credit packs" do
      packs = UsageCredits.configuration.credit_packs
      starter = packs[:starter]
      pro = packs[:pro]
      customer = create_customer

      starter.fulfill_purchase(@user)
      pro.fulfill_purchase(@user)

      assert_equal 6000, @user.credits # 1000 + 5000
      assert_equal 2, @user.credit_history.by_category(:credit_pack_purchase).count
    end

    test "credit pack purchase includes detailed metadata" do
      packs = UsageCredits.configuration.credit_packs
      pack = packs[:starter]
      customer = create_customer

      pack.fulfill_purchase(@user)
      transaction = @user.credit_history.last
      metadata = transaction.metadata

      assert_equal "starter", metadata["pack"]
      assert_equal 4900, metadata["price_cents"]
      assert_equal 1000, metadata["credits"]
      assert_not_nil metadata["purchased_at"]
    end

    private

    def create_customer
      Pay::Customer.create!(
        owner: @user,
        processor: "stripe",
        processor_id: "cus_#{SecureRandom.hex(8)}"
      )
    end
  end
end
