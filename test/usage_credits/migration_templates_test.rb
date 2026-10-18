# frozen_string_literal: true

require "test_helper"
require "erb"

class UsageCredits::MigrationTemplatesTest < ActiveSupport::TestCase
  test "fresh install template matches the wallets-core transfer schema" do
    template = File.read(template_path("create_usage_credits_tables.rb.erb"))

    assert_includes template, 't.string :asset_code, null: false, default: "credits"'
    assert_includes template, "t.bigint :ledger_revision, null: false, default: 0"
    assert_includes template, 't.string :expiration_policy, null: false, default: "preserve"'
    assert_includes template, "t.references :transfer"
    assert_includes template, 'index: { unique: true, name: "index_usage_credits_fulfillments_on_source" }'
    assert_includes template, "add_foreign_key :usage_credits_transactions"
    assert_includes template, '"amount <> 0"'
    assert_includes template, '"from_wallet_id <> to_wallet_id"'
    refute_includes template, "outbound_transaction"
    refute_includes template, "inbound_transaction"
  end

  test "upgrade template uses an explicit up migration without adding new legacy fulfillment foreign keys" do
    template = File.read(template_path("upgrade_usage_credits_to_wallets_core.rb.erb"))

    assert_includes template, "def up"
    assert_includes template, "class UpgradeUsageCreditsToWalletsCore"
    assert_includes template, "add_column :usage_credits_wallets, :asset_code"
    assert_includes template, "add_column :usage_credits_wallets, :ledger_revision, :bigint, null: false, default: 0"
    assert_includes template, "ensure_bigint_column!(:usage_credits_wallets, :balance"
    assert_includes template, "create_table :usage_credits_transfers"
    assert_includes template, 't.string :expiration_policy, null: false, default: "preserve"'
    assert_includes template, "ensure_no_duplicate_fulfillment_sources!"
    assert_includes template, "ensure_transfer_reference!"
    refute_includes template, "outbound_transaction"
    refute_includes template, "inbound_transaction"
    refute_includes template, "add_foreign_key :usage_credits_fulfillments"
  end

  # MySQL refuses a default on a JSON column, and Rails' Trilogy adapter talks
  # to MySQL under its own name, so every path that creates usage_credits
  # tables must recognise both, exactly as the wallets coexistence tables do.
  test "every migration leaves JSON columns without a default on MySQL, under either adapter name" do
    migrations = {
      "install template" => template_migration_class("create_usage_credits_tables.rb.erb"),
      "upgrade template" => template_migration_class("upgrade_usage_credits_to_wallets_core.rb.erb"),
      "dummy install migration" => dummy_migration_class("20250212181807_create_usage_credits_tables.rb"),
      "dummy coexistence migration" => dummy_migration_class("20250417000000_create_wallets_coexistence_tables.rb")
    }

    {"Mysql2" => nil, "Trilogy" => nil, "PostgreSQL" => {}, "SQLite" => {}}.each do |adapter_name, expected_default|
      migrations.each do |name, migration_class|
        migration = migration_class.new
        migration.stubs(:connection).returns(stub(adapter_name: adapter_name))
        default = migration.send(:json_column_default)

        if expected_default.nil?
          assert_nil default, "#{name} must leave JSON columns without a default on #{adapter_name}"
        else
          assert_equal expected_default, default, "#{name} on #{adapter_name}"
        end
      end
    end
  end

  private

  def template_path(filename)
    File.expand_path("../../lib/generators/usage_credits/templates/#{filename}", __dir__)
  end

  def template_migration_class(filename)
    source = ERB.new(File.read(template_path(filename))).result_with_hash(
      migration_version: "[#{ActiveRecord::VERSION::STRING.to_f}]"
    )
    migration_class_from(source, template_path(filename))
  end

  def dummy_migration_class(filename)
    path = File.expand_path("../dummy/db/migrate/#{filename}", __dir__)
    migration_class_from(File.read(path), path)
  end

  # In a namespace of its own, so loading a migration never clashes with a
  # constant the app or another test defines.
  def migration_class_from(source, path)
    namespace = Module.new
    namespace.module_eval(source, path, 1)
    namespace.const_get(source[/^class (\w+) </, 1])
  end
end
