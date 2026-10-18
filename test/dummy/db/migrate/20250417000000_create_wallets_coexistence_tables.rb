# frozen_string_literal: true

# The standalone `wallets_*` tables a host app gets from `wallets:install`
# (wallets 0.4), so the dummy app can run `has_wallets` beside `has_credits`.
# `Wallets::Wallet` keeps holds, so it needs the holds table and the
# `ledger_revision` column: without them every balance read on it raises.
class CreateWalletsCoexistenceTables < ActiveRecord::Migration[7.2]
  def change
    primary_key_type, foreign_key_type = primary_and_foreign_key_types

    create_table :teams, id: primary_key_type do |t|
      t.string :name

      t.timestamps
    end

    create_table :wallets_wallets, id: primary_key_type do |t|
      t.references :owner, polymorphic: true, null: false, type: foreign_key_type
      t.string :asset_code, null: false
      t.bigint :balance, null: false, default: 0
      # Incremented by every command, so a stale database snapshot can always
      # be told from a current one, whatever the clock or a `touch` says.
      t.bigint :ledger_revision, null: false, default: 0
      t.send(json_column_type, :metadata, null: false, default: json_column_default)

      t.timestamps
    end

    add_index :wallets_wallets, [:owner_type, :owner_id, :asset_code], unique: true, name: "index_wallets_on_owner_and_asset_code"

    create_table :wallets_transfers, id: primary_key_type do |t|
      t.references :from_wallet, null: false, type: foreign_key_type, foreign_key: {to_table: :wallets_wallets}
      t.references :to_wallet, null: false, type: foreign_key_type, foreign_key: {to_table: :wallets_wallets}
      t.string :asset_code, null: false
      t.bigint :amount, null: false
      t.string :category, null: false, default: "transfer"
      t.string :expiration_policy, null: false, default: "preserve"
      t.send(json_column_type, :metadata, null: false, default: json_column_default)

      t.timestamps
    end

    create_table :wallets_transactions, id: primary_key_type do |t|
      t.references :wallet, null: false, type: foreign_key_type, foreign_key: {to_table: :wallets_wallets}
      t.bigint :amount, null: false
      t.string :category, null: false
      t.datetime :expires_at
      t.references :transfer, type: foreign_key_type, foreign_key: {to_table: :wallets_transfers}
      t.send(json_column_type, :metadata, null: false, default: json_column_default)

      t.timestamps
    end

    create_table :wallets_allocations, id: primary_key_type do |t|
      t.references :transaction, null: false, type: foreign_key_type,
        foreign_key: {to_table: :wallets_transactions},
        index: {name: "index_wallets_allocations_on_transaction_id"}
      t.references :source_transaction, null: false, type: foreign_key_type,
        foreign_key: {to_table: :wallets_transactions},
        index: {name: "index_wallets_allocations_on_source_transaction_id"}
      t.bigint :amount, null: false

      t.timestamps
    end

    # Holds keep value in the ledger but out of the available balance: a hold
    # on one credit, a hold on the whole wallet, or a reservation of an amount.
    # Exactly as wallets 0.4's install template defines it.
    create_table :wallets_holds, id: primary_key_type do |t|
      t.references :wallet, null: false, type: foreign_key_type,
        foreign_key: {to_table: :wallets_wallets},
        index: false

      # The credit a credit hold covers. Wallet holds and reservations have none.
      t.references :transaction, type: foreign_key_type,
        foreign_key: {to_table: :wallets_transactions},
        index: false

      # The debit a reservation was captured into.
      t.references :capture_transaction, type: foreign_key_type,
        foreign_key: {to_table: :wallets_transactions},
        index: {unique: true, name: "index_wallets_holds_on_capture_tx"}

      t.bigint :amount # reservations only
      t.string :category, null: false
      t.datetime :releases_at # the scheduled end
      t.datetime :released_at # the explicit end: a release or a capture
      t.string :release_reason
      t.send(json_column_type, :metadata, null: false, default: json_column_default)
      t.send(json_column_type, :release_metadata, null: false, default: json_column_default)

      t.timestamps

      # Inside the table, as in the install template, so that MySQL can drop
      # it without first dropping an index a foreign key still needs.
      t.index [:wallet_id, :released_at], name: "index_wallets_holds_on_wallet_and_released_at"
      t.index [:transaction_id, :released_at], name: "index_wallets_holds_on_tx_and_released_at"
      t.index :releases_at, name: "index_wallets_holds_on_releases_at"

      t.check_constraint "amount IS NULL OR amount > 0", name: "check_wallets_holds_amount_positive"
      # A credit hold holds the credit's whole remaining value, never an amount.
      t.check_constraint "transaction_id IS NULL OR amount IS NULL", name: "check_wallets_holds_credit_hold_has_no_amount"
      # Only an ended reservation can name the debit it was captured into.
      t.check_constraint "capture_transaction_id IS NULL OR " \
                         "(transaction_id IS NULL AND amount IS NOT NULL AND released_at IS NOT NULL)",
        name: "check_wallets_holds_capture_ends_reservation"
    end

    add_index :wallets_transactions, :category
    add_index :wallets_transactions, :expires_at
    add_index :wallets_transactions, [:wallet_id, :amount], name: "index_wallets_transactions_on_wallet_id_and_amount"
    add_index :wallets_transactions, [:expires_at, :id], name: "index_wallets_transactions_on_expires_at_and_id"
    add_index :wallets_allocations, [:transaction_id, :source_transaction_id], name: "index_wallets_allocations_on_tx_and_source_tx"
    add_index :wallets_transfers, [:from_wallet_id, :to_wallet_id, :asset_code], name: "index_wallets_transfers_on_wallets_and_asset"
  end

  private

  def primary_and_foreign_key_types
    config = Rails.configuration.generators
    setting = config.options[config.orm][:primary_key_type]
    primary_key_type = setting || :primary_key
    foreign_key_type = setting || :bigint
    [primary_key_type, foreign_key_type]
  end

  def json_column_type
    return :jsonb if connection.adapter_name.match?(/postg/i) # PostgreSQL, and PostGIS, which is PostgreSQL under another name

    :json
  end

  # MySQL does not allow defaults on JSON columns, so models treat nil metadata
  # the same as an empty hash when records are loaded. Rails' Trilogy adapter
  # talks to MySQL too, under its own name.
  def json_column_default
    return nil if connection.adapter_name.match?(/mysql|trilogy/i)

    {}
  end
end
