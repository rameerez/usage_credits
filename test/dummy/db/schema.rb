# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.1].define(version: 2025_04_17_000000) do
  create_table "pay_charges", force: :cascade do |t|
    t.integer "amount", null: false
    t.integer "amount_refunded"
    t.integer "application_fee_amount"
    t.datetime "created_at", null: false
    t.string "currency"
    t.bigint "customer_id", null: false
    t.json "data"
    t.json "metadata"
    t.json "object"
    t.string "processor_id", null: false
    t.string "stripe_account"
    t.bigint "subscription_id"
    t.string "type"
    t.datetime "updated_at", null: false
    t.index ["customer_id", "processor_id"], name: "index_pay_charges_on_customer_id_and_processor_id", unique: true
    t.index ["subscription_id"], name: "index_pay_charges_on_subscription_id"
  end

  create_table "pay_customers", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.json "data"
    t.boolean "default"
    t.datetime "deleted_at", precision: nil
    t.json "object"
    t.bigint "owner_id"
    t.string "owner_type"
    t.string "processor", null: false
    t.string "processor_id"
    t.string "stripe_account"
    t.string "type"
    t.datetime "updated_at", null: false
    t.index ["owner_type", "owner_id", "deleted_at"], name: "pay_customer_owner_index", unique: true
    t.index ["processor", "processor_id"], name: "index_pay_customers_on_processor_and_processor_id", unique: true
  end

  create_table "pay_merchants", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.json "data"
    t.boolean "default"
    t.bigint "owner_id"
    t.string "owner_type"
    t.string "processor", null: false
    t.string "processor_id"
    t.string "type"
    t.datetime "updated_at", null: false
    t.index ["owner_type", "owner_id", "processor"], name: "index_pay_merchants_on_owner_type_and_owner_id_and_processor"
  end

  create_table "pay_payment_methods", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "customer_id", null: false
    t.json "data"
    t.boolean "default"
    t.string "payment_method_type"
    t.string "processor_id", null: false
    t.string "stripe_account"
    t.string "type"
    t.datetime "updated_at", null: false
    t.index ["customer_id", "processor_id"], name: "index_pay_payment_methods_on_customer_id_and_processor_id", unique: true
  end

  create_table "pay_subscriptions", force: :cascade do |t|
    t.decimal "application_fee_percent", precision: 8, scale: 2
    t.datetime "created_at", null: false
    t.datetime "current_period_end", precision: nil
    t.datetime "current_period_start", precision: nil
    t.bigint "customer_id", null: false
    t.json "data"
    t.datetime "ends_at", precision: nil
    t.json "metadata"
    t.boolean "metered"
    t.string "name", null: false
    t.json "object"
    t.string "pause_behavior"
    t.datetime "pause_resumes_at", precision: nil
    t.datetime "pause_starts_at", precision: nil
    t.string "payment_method_id"
    t.string "processor_id", null: false
    t.string "processor_plan", null: false
    t.integer "quantity", default: 1, null: false
    t.string "status", null: false
    t.string "stripe_account"
    t.datetime "trial_ends_at", precision: nil
    t.string "type"
    t.datetime "updated_at", null: false
    t.index ["customer_id", "processor_id"], name: "index_pay_subscriptions_on_customer_id_and_processor_id", unique: true
    t.index ["metered"], name: "index_pay_subscriptions_on_metered"
    t.index ["pause_starts_at"], name: "index_pay_subscriptions_on_pause_starts_at"
  end

  create_table "pay_webhooks", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.json "event"
    t.string "event_type"
    t.string "processor"
    t.datetime "updated_at", null: false
  end

  create_table "teams", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "name"
    t.datetime "updated_at", null: false
  end

  create_table "usage_credits_allocations", force: :cascade do |t|
    t.bigint "amount", null: false
    t.datetime "created_at", null: false
    t.bigint "source_transaction_id", null: false
    t.bigint "transaction_id", null: false
    t.datetime "updated_at", null: false
    t.index ["source_transaction_id"], name: "index_usage_credits_allocations_on_source_tx_id"
    t.index ["transaction_id", "source_transaction_id"], name: "index_usage_credits_allocations_on_tx_and_source_tx"
    t.index ["transaction_id"], name: "index_allocations_on_transaction_id"
  end

  create_table "usage_credits_fulfillments", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "credits_last_fulfillment", null: false
    t.string "fulfillment_period"
    t.string "fulfillment_type", null: false
    t.datetime "last_fulfilled_at"
    t.json "metadata", default: {}, null: false
    t.datetime "next_fulfillment_at"
    t.bigint "source_id"
    t.string "source_type"
    t.datetime "stops_at"
    t.datetime "updated_at", null: false
    t.bigint "wallet_id", null: false
    t.index ["fulfillment_type"], name: "index_usage_credits_fulfillments_on_fulfillment_type"
    t.index ["next_fulfillment_at"], name: "index_usage_credits_fulfillments_on_next_fulfillment_at"
    t.index ["source_type", "source_id"], name: "index_usage_credits_fulfillments_on_source"
    t.index ["wallet_id"], name: "index_usage_credits_fulfillments_on_wallet_id"
  end

  create_table "usage_credits_transactions", force: :cascade do |t|
    t.bigint "amount", null: false
    t.string "category", null: false
    t.datetime "created_at", null: false
    t.datetime "expires_at"
    t.bigint "fulfillment_id"
    t.json "metadata", default: {}, null: false
    t.bigint "transfer_id"
    t.datetime "updated_at", null: false
    t.bigint "wallet_id", null: false
    t.index ["category"], name: "index_usage_credits_transactions_on_category"
    t.index ["expires_at", "id"], name: "index_usage_credits_transactions_on_expires_at_and_id"
    t.index ["expires_at"], name: "index_usage_credits_transactions_on_expires_at"
    t.index ["fulfillment_id"], name: "index_usage_credits_transactions_on_fulfillment_id"
    t.index ["transfer_id"], name: "index_usage_credits_transactions_on_transfer_id"
    t.index ["wallet_id", "amount"], name: "index_usage_credits_transactions_on_wallet_id_and_amount"
    t.index ["wallet_id"], name: "index_usage_credits_transactions_on_wallet_id"
  end

  create_table "usage_credits_transfers", force: :cascade do |t|
    t.bigint "amount", null: false
    t.string "asset_code", default: "credits", null: false
    t.string "category", default: "transfer", null: false
    t.datetime "created_at", null: false
    t.string "expiration_policy", default: "preserve", null: false
    t.bigint "from_wallet_id", null: false
    t.json "metadata", default: {}, null: false
    t.bigint "to_wallet_id", null: false
    t.datetime "updated_at", null: false
    t.index ["from_wallet_id", "to_wallet_id", "asset_code"], name: "index_usage_credits_transfers_on_wallets_and_asset"
    t.index ["from_wallet_id"], name: "index_usage_credits_transfers_on_from_wallet_id"
    t.index ["to_wallet_id"], name: "index_usage_credits_transfers_on_to_wallet_id"
  end

  create_table "usage_credits_wallets", force: :cascade do |t|
    t.string "asset_code", default: "credits", null: false
    t.bigint "balance", default: 0, null: false
    t.datetime "created_at", null: false
    t.json "metadata", default: {}, null: false
    t.bigint "owner_id", null: false
    t.string "owner_type", null: false
    t.datetime "updated_at", null: false
    t.index ["owner_type", "owner_id", "asset_code"], name: "index_usage_credits_wallets_on_owner_and_asset", unique: true
    t.index ["owner_type", "owner_id"], name: "index_usage_credits_wallets_on_owner"
  end

  create_table "users", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "email"
    t.string "name"
    t.datetime "updated_at", null: false
  end

  create_table "wallets_allocations", force: :cascade do |t|
    t.bigint "amount", null: false
    t.datetime "created_at", null: false
    t.bigint "source_transaction_id", null: false
    t.bigint "transaction_id", null: false
    t.datetime "updated_at", null: false
    t.index ["source_transaction_id"], name: "index_wallets_allocations_on_source_transaction_id"
    t.index ["transaction_id", "source_transaction_id"], name: "index_wallets_allocations_on_tx_and_source_tx"
    t.index ["transaction_id"], name: "index_wallets_allocations_on_transaction_id"
  end

  create_table "wallets_transactions", force: :cascade do |t|
    t.bigint "amount", null: false
    t.string "category", null: false
    t.datetime "created_at", null: false
    t.datetime "expires_at"
    t.json "metadata", default: {}, null: false
    t.bigint "transfer_id"
    t.datetime "updated_at", null: false
    t.bigint "wallet_id", null: false
    t.index ["category"], name: "index_wallets_transactions_on_category"
    t.index ["expires_at", "id"], name: "index_wallets_transactions_on_expires_at_and_id"
    t.index ["expires_at"], name: "index_wallets_transactions_on_expires_at"
    t.index ["transfer_id"], name: "index_wallets_transactions_on_transfer_id"
    t.index ["wallet_id", "amount"], name: "index_wallets_transactions_on_wallet_id_and_amount"
    t.index ["wallet_id"], name: "index_wallets_transactions_on_wallet_id"
  end

  create_table "wallets_transfers", force: :cascade do |t|
    t.bigint "amount", null: false
    t.string "asset_code", null: false
    t.string "category", default: "transfer", null: false
    t.datetime "created_at", null: false
    t.string "expiration_policy", default: "preserve", null: false
    t.bigint "from_wallet_id", null: false
    t.json "metadata", default: {}, null: false
    t.bigint "to_wallet_id", null: false
    t.datetime "updated_at", null: false
    t.index ["from_wallet_id", "to_wallet_id", "asset_code"], name: "index_wallets_transfers_on_wallets_and_asset"
    t.index ["from_wallet_id"], name: "index_wallets_transfers_on_from_wallet_id"
    t.index ["to_wallet_id"], name: "index_wallets_transfers_on_to_wallet_id"
  end

  create_table "wallets_wallets", force: :cascade do |t|
    t.string "asset_code", null: false
    t.bigint "balance", default: 0, null: false
    t.datetime "created_at", null: false
    t.json "metadata", default: {}, null: false
    t.bigint "owner_id", null: false
    t.string "owner_type", null: false
    t.datetime "updated_at", null: false
    t.index ["owner_type", "owner_id", "asset_code"], name: "index_wallets_on_owner_and_asset_code", unique: true
    t.index ["owner_type", "owner_id"], name: "index_wallets_wallets_on_owner"
  end

  add_foreign_key "pay_charges", "pay_customers", column: "customer_id"
  add_foreign_key "pay_charges", "pay_subscriptions", column: "subscription_id"
  add_foreign_key "pay_payment_methods", "pay_customers", column: "customer_id"
  add_foreign_key "pay_subscriptions", "pay_customers", column: "customer_id"
  add_foreign_key "usage_credits_allocations", "usage_credits_transactions", column: "source_transaction_id"
  add_foreign_key "usage_credits_allocations", "usage_credits_transactions", column: "transaction_id"
  add_foreign_key "usage_credits_fulfillments", "usage_credits_wallets", column: "wallet_id"
  add_foreign_key "usage_credits_transactions", "usage_credits_transfers", column: "transfer_id"
  add_foreign_key "usage_credits_transactions", "usage_credits_wallets", column: "wallet_id"
  add_foreign_key "usage_credits_transfers", "usage_credits_wallets", column: "from_wallet_id"
  add_foreign_key "usage_credits_transfers", "usage_credits_wallets", column: "to_wallet_id"
  add_foreign_key "wallets_allocations", "wallets_transactions", column: "source_transaction_id"
  add_foreign_key "wallets_allocations", "wallets_transactions", column: "transaction_id"
  add_foreign_key "wallets_transactions", "wallets_transfers", column: "transfer_id"
  add_foreign_key "wallets_transactions", "wallets_wallets", column: "wallet_id"
  add_foreign_key "wallets_transfers", "wallets_wallets", column: "from_wallet_id"
  add_foreign_key "wallets_transfers", "wallets_wallets", column: "to_wallet_id"
end
