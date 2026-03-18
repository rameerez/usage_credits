# frozen_string_literal: true

require "test_helper"
require "erb"
require "fileutils"
require "tmpdir"

class UsageCredits::UpgradeMigrationTest < ActiveSupport::TestCase
  self.use_transactional_tests = false

  class TemporaryRecord < ActiveRecord::Base
    self.abstract_class = true
  end

  class TemporaryConnectionRecord < TemporaryRecord
    self.abstract_class = true
  end

  def setup
    super

    @tmpdir = Dir.mktmpdir("usage-credits-upgrade")
    @database_path = File.join(@tmpdir, "upgrade.sqlite3")

    @migration_base = TemporaryConnectionRecord
    @migration_base.establish_connection(adapter: "sqlite3", database: @database_path)
    @connection = @migration_base.connection

    create_pre_1_0_schema!
    seed_pre_1_0_data!
  end

  def teardown
    super
  end

  def after_teardown
    super
    @migration_base.connection_pool.disconnect! if defined?(@migration_base) && @migration_base&.connection_pool
    FileUtils.remove_entry(@tmpdir) if @tmpdir && File.exist?(@tmpdir)
  end

  test "upgrade migration preserves pre-1.0 data while adding the wallets core schema" do
    run_upgrade_migration!

    wallet_row = @connection.select_one("SELECT * FROM usage_credits_wallets WHERE id = 1")
    assert_equal "User", wallet_row["owner_type"]
    assert_equal 42, wallet_row["owner_id"]
    assert_equal 150, wallet_row["balance"]
    assert_equal "credits", wallet_row["asset_code"]

    transaction_rows = @connection.exec_query("SELECT id, wallet_id, amount, category, transfer_id FROM usage_credits_transactions ORDER BY id").to_a
    assert_equal [
      { "id" => 1, "wallet_id" => 1, "amount" => 200, "category" => "signup_bonus", "transfer_id" => nil },
      { "id" => 2, "wallet_id" => 1, "amount" => -50, "category" => "operation_charge", "transfer_id" => nil }
    ], transaction_rows

    allocation_row = @connection.select_one("SELECT * FROM usage_credits_allocations WHERE id = 1")
    assert_equal 50, allocation_row["amount"]
    assert_equal 2, allocation_row["transaction_id"]
    assert_equal 1, allocation_row["source_transaction_id"]

    fulfillment_row = @connection.select_one("SELECT * FROM usage_credits_fulfillments WHERE id = 1")
    assert_equal 1, fulfillment_row["wallet_id"]
    assert_equal 200, fulfillment_row["credits_last_fulfillment"]
    assert_equal "signup_fulfillment", fulfillment_row["fulfillable_type"]
    assert_equal 7, fulfillment_row["fulfillable_id"]

    assert_includes @connection.tables, "usage_credits_transfers"
    assert_equal 0, @connection.select_value("SELECT COUNT(*) FROM usage_credits_transfers")

    wallet_index = @connection.indexes(:usage_credits_wallets).find { |index| index.name == "index_usage_credits_wallets_on_owner_and_asset" }
    assert wallet_index, "expected owner/asset index to be created"
    assert wallet_index.unique
    assert_equal %w[owner_type owner_id asset_code], wallet_index.columns

    transfers_index = @connection.indexes(:usage_credits_transfers).find { |index| index.name == "index_usage_credits_transfers_on_wallets_and_asset" }
    assert transfers_index, "expected transfers wallet/asset index to be created"

    wallet_balance_column = @connection.columns(:usage_credits_wallets).find { |column| column.name == "balance" }
    transaction_amount_column = @connection.columns(:usage_credits_transactions).find { |column| column.name == "amount" }
    allocation_amount_column = @connection.columns(:usage_credits_allocations).find { |column| column.name == "amount" }
    fulfillment_amount_column = @connection.columns(:usage_credits_fulfillments).find { |column| column.name == "credits_last_fulfillment" }
    transfer_amount_column = @connection.columns(:usage_credits_transfers).find { |column| column.name == "amount" }
    transfer_policy_column = @connection.columns(:usage_credits_transfers).find { |column| column.name == "expiration_policy" }

    assert_equal "bigint", wallet_balance_column.sql_type
    assert_equal "bigint", transaction_amount_column.sql_type
    assert_equal "bigint", allocation_amount_column.sql_type
    assert_equal "bigint", fulfillment_amount_column.sql_type
    assert_equal "bigint", transfer_amount_column.sql_type
    assert_equal "preserve", transfer_policy_column.default

    transfer_reference = @connection.columns(:usage_credits_transactions).find { |column| column.name == "transfer_id" }

    assert transfer_reference
    refute @connection.columns(:usage_credits_transfers).any? { |column| column.name == "outbound_transaction_id" }
    refute @connection.columns(:usage_credits_transfers).any? { |column| column.name == "inbound_transaction_id" }
  end

  private

  def create_pre_1_0_schema!
    @connection.create_table :usage_credits_wallets do |t|
      t.string :owner_type, null: false
      t.integer :owner_id, null: false
      t.integer :balance, null: false, default: 0
      t.timestamps
    end

    @connection.create_table :usage_credits_transactions do |t|
      t.references :wallet, null: false
      t.references :fulfillment
      t.integer :amount, null: false
      t.string :category, null: false
      t.send(json_column_type, :metadata, default: json_column_default)
      t.datetime :expires_at
      t.integer :balance_before
      t.integer :balance_after
      t.timestamps
    end

    @connection.create_table :usage_credits_allocations do |t|
      t.references :transaction, null: false
      t.references :source_transaction, null: false
      t.integer :amount, null: false
      t.timestamps
    end

    @connection.create_table :usage_credits_fulfillments do |t|
      t.references :wallet
      t.string :fulfillable_type, null: false
      t.integer :fulfillable_id, null: false
      t.datetime :fulfilled_at
      t.integer :credits_last_fulfillment, null: false, default: 0
      t.send(json_column_type, :metadata, default: json_column_default)
      t.timestamps
    end
  end

  def seed_pre_1_0_data!
    now = Time.current

    insert_row :usage_credits_wallets,
      id: 1,
      owner_type: "User",
      owner_id: 42,
      balance: 150,
      created_at: now,
      updated_at: now

    insert_row :usage_credits_transactions,
      id: 1,
      wallet_id: 1,
      fulfillment_id: 1,
      amount: 200,
      category: "signup_bonus",
      metadata: json_payload(reason: "welcome"),
      balance_before: 0,
      balance_after: 200,
      created_at: now,
      updated_at: now

    insert_row :usage_credits_transactions,
      id: 2,
      wallet_id: 1,
      fulfillment_id: nil,
      amount: -50,
      category: "operation_charge",
      metadata: json_payload(operation: "generate_report"),
      balance_before: 200,
      balance_after: 150,
      created_at: now,
      updated_at: now

    insert_row :usage_credits_allocations,
      id: 1,
      transaction_id: 2,
      source_transaction_id: 1,
      amount: 50,
      created_at: now,
      updated_at: now

    insert_row :usage_credits_fulfillments,
      id: 1,
      wallet_id: 1,
      fulfillable_type: "signup_fulfillment",
      fulfillable_id: 7,
      fulfilled_at: now,
      credits_last_fulfillment: 200,
      metadata: json_payload(source: "signup"),
      created_at: now,
      updated_at: now
  end

  def run_upgrade_migration!
    migration_class = load_upgrade_migration_class
    migration = migration_class.new
    migration.verbose = false
    migration.exec_migration(@connection, :up)
  end

  def load_upgrade_migration_class
    source = ERB.new(File.read(template_path("upgrade_usage_credits_to_wallets_core.rb.erb"))).result_with_hash(
      migration_version: "[#{ActiveRecord::VERSION::STRING.to_f}]"
    )

    mod = Module.new
    mod.module_eval(source, template_path("upgrade_usage_credits_to_wallets_core.rb.erb"), 1)
    mod.const_get(:UpgradeUsageCreditsToWalletsCore)
  end

  def insert_row(table_name, attributes)
    columns = attributes.keys.map(&:to_s)
    values = attributes.values.map { |value| @connection.quote(value) }

    @connection.execute(<<~SQL.squish)
      INSERT INTO #{table_name} (#{columns.join(', ')})
      VALUES (#{values.join(', ')})
    SQL
  end

  def template_path(filename)
    File.expand_path("../../lib/generators/usage_credits/templates/#{filename}", __dir__)
  end

  def json_column_type
    @connection.adapter_name.downcase.include?("postgresql") ? :jsonb : :json
  end

  def json_column_default
    @connection.adapter_name.downcase.include?("mysql") ? nil : {}
  end

  def json_payload(attributes)
    ActiveSupport::JSON.encode(attributes)
  end
end
