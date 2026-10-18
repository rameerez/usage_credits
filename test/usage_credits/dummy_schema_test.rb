# frozen_string_literal: true

require "test_helper"
require "active_record/connection_adapters/sqlite3_adapter"

# The dummy app's db/schema.rb is what `db:schema:load` and `db:test:prepare`
# build a test database from. CI resets its databases through the migrations,
# which also rewrites the file, so a committed schema that drifted from the
# migrations goes unnoticed there and breaks every run that loads it instead.
#
# This test runs every dummy migration against an in-memory SQLite database of
# its own and compares the tables and columns they create with the ones the
# schema file declares. Names only: they are the same whichever adapter dumped
# the file, and on every supported Rails.
class UsageCredits::DummySchemaTest < ActiveSupport::TestCase
  SCHEMA_PATH = File.expand_path("../dummy/db/schema.rb", __dir__)
  MIGRATIONS = Dir[File.expand_path("../dummy/db/migrate/*.rb", __dir__)].sort.freeze

  test "the committed dummy schema declares every table and column the migrations create" do
    assert_equal tables_the_migrations_create, tables_the_schema_declares
  end

  test "the committed dummy schema carries the wallets 0.4 tables and columns" do
    declared = tables_the_schema_declares

    assert_includes declared.keys, "wallets_holds"
    assert_includes declared.fetch("usage_credits_wallets"), "ledger_revision"
    assert_includes declared.fetch("wallets_wallets"), "ledger_revision"
  end

  private

  # {table => sorted column names}, primary keys aside.
  def tables_the_schema_declares
    tables = {}
    columns = nil

    File.foreach(SCHEMA_PATH) do |line|
      if (table = line[/\A\s*create_table "([^"]+)"/, 1])
        columns = tables[table] = []
      elsif columns && (column = line[/\A\s*t\.(?!index\b|check_constraint\b)\w+ "([^"]+)"/, 1])
        columns << column
      elsif line.match?(/\A\s*end\s*\z/)
        columns = nil
      end
    end

    tables.sort.to_h { |table, names| [table, names.without("id").sort] }
  end

  def tables_the_migrations_create
    connection = ActiveRecord::ConnectionAdapters::SQLite3Adapter.new(adapter: "sqlite3", database: ":memory:")

    # Pay's migrations ask Pay, not the migration's connection, which JSON
    # type to use (the suite's own database may be PostgreSQL), and its STI
    # migration rewrites existing rows through Pay's models, which read the
    # suite's own database. Only the structure matters here.
    Pay::Adapter.stubs(:json_column_type).returns(:json)
    Pay::Customer.stubs(:find_each)
    Pay::Merchant.stubs(:find_each)

    MIGRATIONS.each do |path|
      migration = migration_class(path).new
      migration.verbose = false
      migration.exec_migration(connection, :up)
    end

    connection.tables.sort.to_h { |table| [table, connection.columns(table).map(&:name).without("id").sort] }
  ensure
    connection&.disconnect!
  end

  # Each migration class in a namespace of its own, so loading them never
  # clashes with a constant the app or another test defines.
  def migration_class(path)
    source = File.read(path)
    namespace = Module.new
    namespace.module_eval(source, path, 1)
    namespace.const_get(source[/^class (\w+) </, 1])
  end
end
