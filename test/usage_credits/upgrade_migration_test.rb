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
    create_pre_1_0_schema!
    seed_pre_1_0_data!

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

    # Pre-1.0 stored balance snapshots inside metadata; they must survive untouched.
    credit_metadata = ActiveSupport::JSON.decode(@connection.select_value("SELECT metadata FROM usage_credits_transactions WHERE id = 1"))
    assert_equal "welcome", credit_metadata["reason"]
    assert_equal 200, credit_metadata["balance_after"]

    allocation_row = @connection.select_one("SELECT * FROM usage_credits_allocations WHERE id = 1")
    assert_equal 50, allocation_row["amount"]
    assert_equal 2, allocation_row["transaction_id"]
    assert_equal 1, allocation_row["source_transaction_id"]

    fulfillment_row = @connection.select_one("SELECT * FROM usage_credits_fulfillments WHERE id = 1")
    assert_equal 1, fulfillment_row["wallet_id"]
    assert_equal 200, fulfillment_row["credits_last_fulfillment"]
    assert_equal "Pay::Charge", fulfillment_row["source_type"]
    assert_equal 7, fulfillment_row["source_id"]
    assert_equal "credit_pack", fulfillment_row["fulfillment_type"]

    assert_includes @connection.tables, "usage_credits_transfers"
    assert_equal 0, @connection.select_value("SELECT COUNT(*) FROM usage_credits_transfers")

    wallet_index = @connection.indexes(:usage_credits_wallets).find { |index| index.name == "index_usage_credits_wallets_on_owner_and_asset" }
    assert wallet_index, "expected owner/asset index to be created"
    assert wallet_index.unique
    assert_equal %w[owner_type owner_id asset_code], wallet_index.columns

    transfers_index = @connection.indexes(:usage_credits_transfers).find { |index| index.name == "index_usage_credits_transfers_on_wallets_and_asset" }
    assert transfers_index, "expected transfers wallet/asset index to be created"

    # Pre-1.0 index names are intentionally preserved (no renames on production tables).
    legacy_allocation_index = @connection.indexes(:usage_credits_allocations).find { |index| index.name == "index_allocations_on_tx_and_source_tx" }
    assert legacy_allocation_index, "expected pre-1.0 allocation index name to be preserved"

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

  test "upgrade migration aborts before touching the schema when duplicate owner wallets exist" do
    create_pre_1_0_schema!
    seed_pre_1_0_data!

    # The pre-1.0 schema never enforced one-wallet-per-owner, so a race could
    # have created duplicates. Simulate that exact production scenario.
    insert_row :usage_credits_wallets,
      id: 2,
      owner_type: "User",
      owner_id: 42,
      balance: 25,
      created_at: Time.current,
      updated_at: Time.current

    error = assert_raises(StandardError) { run_upgrade_migration! }
    assert_match(/more than one usage_credits wallet/, error.message)
    assert_match(/User#42 \(2 wallets\)/, error.message)
    assert_match(/No schema changes have been applied yet/, error.message)

    # The database must be completely untouched so the user can fix data and re-run.
    refute @connection.columns(:usage_credits_wallets).any? { |column| column.name == "asset_code" }
    refute_includes @connection.tables, "usage_credits_transfers"
    refute @connection.columns(:usage_credits_transactions).any? { |column| column.name == "transfer_id" }
  end

  test "upgrade migration is safe to re-run after a completed or interrupted attempt" do
    create_pre_1_0_schema!
    seed_pre_1_0_data!

    run_upgrade_migration!
    run_upgrade_migration!

    assert_equal 1, @connection.indexes(:usage_credits_wallets).count { |index| index.name == "index_usage_credits_wallets_on_owner_and_asset" }
    assert_equal 150, @connection.select_value("SELECT balance FROM usage_credits_wallets WHERE id = 1")
  end

  test "upgrade migration tells fresh apps to use the install generator instead" do
    error = assert_raises(StandardError) { run_upgrade_migration! }
    assert_match(/No usage_credits tables found/, error.message)
    assert_match(/usage_credits:install/, error.message)
  end

  private

  # Mirrors the actual 0.5.0 install template (lib/generators/usage_credits/templates/
  # create_usage_credits_tables.rb.erb on the 0.5.0 tag) so we test the upgrade
  # against the schema real production apps are coming from.
  def create_pre_1_0_schema!
    @connection.create_table :usage_credits_wallets do |t|
      t.references :owner, polymorphic: true, null: false
      t.integer :balance, null: false, default: 0
      t.json :metadata, null: false, default: {}

      t.timestamps
    end

    @connection.create_table :usage_credits_transactions do |t|
      t.references :wallet, null: false
      t.integer :amount, null: false
      t.string :category, null: false
      t.datetime :expires_at
      t.references :fulfillment
      t.json :metadata, null: false, default: {}

      t.timestamps
    end

    @connection.create_table :usage_credits_fulfillments do |t|
      t.references :wallet, null: false
      t.references :source, polymorphic: true
      t.integer :credits_last_fulfillment, null: false
      t.string :fulfillment_type, null: false
      t.datetime :last_fulfilled_at
      t.datetime :next_fulfillment_at
      t.string :fulfillment_period
      t.datetime :stops_at
      t.json :metadata, null: false, default: {}

      t.timestamps
    end

    @connection.create_table :usage_credits_allocations do |t|
      t.references :transaction, null: false,
                                 foreign_key: { to_table: :usage_credits_transactions },
                                 index: { name: "index_allocations_on_transaction_id" }
      t.references :source_transaction, null: false,
                                        foreign_key: { to_table: :usage_credits_transactions },
                                        index: { name: "index_allocations_on_source_transaction_id" }
      t.integer :amount, null: false

      t.timestamps
    end

    @connection.add_index :usage_credits_transactions, :category
    @connection.add_index :usage_credits_transactions, :expires_at
    @connection.add_index :usage_credits_transactions, [:expires_at, :id], name: "index_transactions_on_expires_at_and_id"
    @connection.add_index :usage_credits_transactions, [:wallet_id, :amount], name: "index_transactions_on_wallet_id_and_amount"
    @connection.add_index :usage_credits_allocations, [:transaction_id, :source_transaction_id], name: "index_allocations_on_tx_and_source_tx"
    @connection.add_index :usage_credits_fulfillments, :next_fulfillment_at
    @connection.add_index :usage_credits_fulfillments, :fulfillment_type
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

    # 0.5.0 stored balance snapshots in metadata, not in dedicated columns.
    insert_row :usage_credits_transactions,
      id: 1,
      wallet_id: 1,
      fulfillment_id: 1,
      amount: 200,
      category: "signup_bonus",
      metadata: json_payload(reason: "welcome", balance_before: 0, balance_after: 200),
      created_at: now,
      updated_at: now

    insert_row :usage_credits_transactions,
      id: 2,
      wallet_id: 1,
      fulfillment_id: nil,
      amount: -50,
      category: "operation_charge",
      metadata: json_payload(operation: "generate_report", balance_before: 200, balance_after: 150),
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
      source_type: "Pay::Charge",
      source_id: 7,
      credits_last_fulfillment: 200,
      fulfillment_type: "credit_pack",
      last_fulfilled_at: now,
      metadata: json_payload(purchase: "starter_pack"),
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

  def json_payload(attributes)
    ActiveSupport::JSON.encode(attributes)
  end
end
