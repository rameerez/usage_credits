# frozen_string_literal: true

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
      t.send(json_column_type, :metadata, null: false, default: json_column_default)

      t.timestamps
    end

    add_index :wallets_wallets, [:owner_type, :owner_id, :asset_code], unique: true, name: "index_wallets_on_owner_and_asset_code"

    create_table :wallets_transfers, id: primary_key_type do |t|
      t.references :from_wallet, null: false, type: foreign_key_type, foreign_key: { to_table: :wallets_wallets }
      t.references :to_wallet, null: false, type: foreign_key_type, foreign_key: { to_table: :wallets_wallets }
      t.string :asset_code, null: false
      t.bigint :amount, null: false
      t.string :category, null: false, default: "transfer"
      t.string :expiration_policy, null: false, default: "preserve"
      t.send(json_column_type, :metadata, null: false, default: json_column_default)

      t.timestamps
    end

    create_table :wallets_transactions, id: primary_key_type do |t|
      t.references :wallet, null: false, type: foreign_key_type, foreign_key: { to_table: :wallets_wallets }
      t.bigint :amount, null: false
      t.string :category, null: false
      t.datetime :expires_at
      t.references :transfer, type: foreign_key_type, foreign_key: { to_table: :wallets_transfers }
      t.send(json_column_type, :metadata, null: false, default: json_column_default)

      t.timestamps
    end

    create_table :wallets_allocations, id: primary_key_type do |t|
      t.references :transaction, null: false, type: foreign_key_type,
                                 foreign_key: { to_table: :wallets_transactions },
                                 index: { name: "index_wallets_allocations_on_transaction_id" }
      t.references :source_transaction, null: false, type: foreign_key_type,
                                        foreign_key: { to_table: :wallets_transactions },
                                        index: { name: "index_wallets_allocations_on_source_transaction_id" }
      t.bigint :amount, null: false

      t.timestamps
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
    return :jsonb if connection.adapter_name.downcase.include?("postgresql")

    :json
  end

  def json_column_default
    return nil if connection.adapter_name.downcase.include?("mysql")

    {}
  end
end
