# frozen_string_literal: true

require "test_helper"

module UsageCredits
  # Regression guard for the fresh-install crash: apps that install ONLY
  # usage_credits (no wallets_* tables) crashed on their first wallet
  # creation, because ActiveRecord builds a subclass's attribute methods on
  # its parent's ("superclass.define_attribute_methods unless base_class?")
  # and the models used to subclass the CONCRETE Wallets::* classes — forcing
  # a schema load of tables that don't exist in embedded-only installs.
  #
  # The dummy app migrates both schemas, so the crash can't reproduce here
  # directly; these invariants are the exact conditions that prevent it.
  class EmbeddedBaseClassTest < ActiveSupport::TestCase
    EMBEDDED_MODELS = [
      UsageCredits::Wallet,
      UsageCredits::Transaction,
      UsageCredits::Allocation,
      UsageCredits::Transfer
    ].freeze

    test "every embedded model is its own base_class under an abstract parent" do
      EMBEDDED_MODELS.each do |model|
        assert_equal model, model.base_class,
          "#{model} must be its own base_class — otherwise ActiveRecord " \
          "loads the base wallets_* schema, which fresh embedded-only " \
          "installs don't have"
        assert_predicate model.superclass, :abstract_class?,
          "#{model}'s parent (#{model.superclass}) must be abstract"
      end
    end

    test "embedded models keep their own tables and never point at wallets_*" do
      assert_equal "usage_credits_wallets", UsageCredits::Wallet.table_name
      assert_equal "usage_credits_transactions", UsageCredits::Transaction.table_name
      assert_equal "usage_credits_allocations", UsageCredits::Allocation.table_name
      assert_equal "usage_credits_transfers", UsageCredits::Transfer.table_name
    end

    test "low_balance_threshold accepts the DSL form its own template shows" do
      config = UsageCredits::Configuration.new
      config.low_balance_threshold = 100.credits
      assert_equal 100, config.low_balance_threshold

      config.low_balance_threshold = 250
      assert_equal 250, config.low_balance_threshold

      config.low_balance_threshold = nil
      assert_nil config.low_balance_threshold
    end
  end
end
