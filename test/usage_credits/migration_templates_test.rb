# frozen_string_literal: true

require "test_helper"

class UsageCredits::MigrationTemplatesTest < ActiveSupport::TestCase
  test "fresh install template matches the wallets-core transfer schema" do
    template = File.read(template_path("create_usage_credits_tables.rb.erb"))

    assert_includes template, 't.string :asset_code, null: false, default: "credits"'
    assert_includes template, 't.string :expiration_policy, null: false, default: "preserve"'
    assert_includes template, "t.references :transfer"
    refute_includes template, "outbound_transaction"
    refute_includes template, "inbound_transaction"
  end

  test "upgrade template uses an explicit up migration without adding new legacy fulfillment foreign keys" do
    template = File.read(template_path("upgrade_usage_credits_to_wallets_core.rb.erb"))

    assert_includes template, "def up"
    assert_includes template, "class UpgradeUsageCreditsToWalletsCore"
    assert_includes template, "add_column :usage_credits_wallets, :asset_code"
    assert_includes template, "change_column :usage_credits_wallets, :balance, :bigint"
    assert_includes template, "create_table :usage_credits_transfers"
    assert_includes template, 't.string :expiration_policy, null: false, default: "preserve"'
    refute_includes template, "outbound_transaction"
    refute_includes template, "inbound_transaction"
    refute_includes template, "add_foreign_key :usage_credits_fulfillments"
  end

  private

  def template_path(filename)
    File.expand_path("../../lib/generators/usage_credits/templates/#{filename}", __dir__)
  end
end
