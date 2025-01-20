# frozen_string_literal: true

class CreateUsageCreditsTables < ActiveRecord::Migration[8.0]
  def change
    primary_key_type, foreign_key_type = primary_and_foreign_key_types

    create_table :usage_credits_wallets, id: primary_key_type do |t|
      t.references :owner, polymorphic: true, null: false, type: foreign_key_type
      t.integer :balance, null: false, default: 0
      t.send(json_column_type, :metadata, null: false, default: {})

      t.timestamps
    end

    create_table :usage_credits_transactions, id: primary_key_type do |t|
      t.references :wallet, null: false, type: foreign_key_type
      t.references :source, polymorphic: true, type: foreign_key_type
      t.integer :amount, null: false
      t.string :category, null: false
      t.datetime :expires_at
      t.send(json_column_type, :metadata, null: false, default: {})

      t.timestamps
    end

    # Add indexes
    add_index :usage_credits_transactions, :category
    add_index :usage_credits_transactions, :expires_at
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
    return :jsonb if connection.adapter_name.downcase.include?('postgresql')
    :json
  end
end
