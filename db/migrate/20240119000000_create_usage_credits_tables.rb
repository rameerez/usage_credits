# frozen_string_literal: true

class CreateUsageCreditsTables < ActiveRecord::Migration[7.0]
  def change
    create_table :usage_credits_wallets do |t|
      t.references :owner, polymorphic: true, null: false, index: { unique: true }
      t.integer :balance, default: 0, null: false
      t.integer :low_balance_threshold
      t.datetime :credits_expire_at
      t.jsonb :metadata, default: {}, null: false

      t.timestamps
    end

    create_table :usage_credits_transactions do |t|
      t.references :wallet, null: false, foreign_key: { to_table: :usage_credits_wallets }
      t.integer :amount, null: false
      t.string :category, null: false
      t.string :description
      t.jsonb :metadata, default: {}, null: false
      t.datetime :expires_at
      t.string :source_type
      t.bigint :source_id

      t.timestamps

      t.index [:source_type, :source_id]
      t.index :category
      t.index :expires_at
    end

    create_table :usage_credits_operations do |t|
      t.string :name, null: false
      t.string :description
      t.integer :base_cost, null: false
      t.jsonb :cost_rules, default: {}, null: false
      t.jsonb :validation_rules, default: {}, null: false
      t.boolean :active, default: true
      t.jsonb :metadata, default: {}, null: false

      t.timestamps

      t.index :name, unique: true
      t.index :active
    end

    create_table :usage_credits_packs do |t|
      t.string :name, null: false
      t.string :description
      t.integer :credits, null: false
      t.integer :bonus_credits, default: 0
      t.integer :price_cents, null: false
      t.string :price_currency, default: "USD", null: false
      t.boolean :active, default: true
      t.jsonb :metadata, default: {}, null: false

      t.timestamps

      t.index :name, unique: true
      t.index :active
    end
  end
end
