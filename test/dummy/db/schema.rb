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

ActiveRecord::Schema[8.0].define(version: 2025_04_16_000000) do
  create_table "pay_charges", force: :cascade do |t|
    t.bigint "customer_id", null: false
    t.bigint "subscription_id"
    t.string "processor_id", null: false
    t.integer "amount", null: false
    t.string "currency"
    t.integer "application_fee_amount"
    t.integer "amount_refunded"
    t.json "metadata"
    t.json "data"
    t.string "stripe_account"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "type"
    t.json "object"
    t.index ["customer_id", "processor_id"], name: "index_pay_charges_on_customer_id_and_processor_id", unique: true
    t.index ["subscription_id"], name: "index_pay_charges_on_subscription_id"
  end

  create_table "pay_customers", force: :cascade do |t|
    t.string "owner_type"
    t.bigint "owner_id"
    t.string "processor", null: false
    t.string "processor_id"
    t.boolean "default"
    t.json "data"
    t.string "stripe_account"
    t.datetime "deleted_at", precision: nil
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "type"
    t.json "object"
    t.index ["owner_type", "owner_id", "deleted_at"], name: "pay_customer_owner_index", unique: true
    t.index ["processor", "processor_id"], name: "index_pay_customers_on_processor_and_processor_id", unique: true
  end

  create_table "pay_merchants", force: :cascade do |t|
    t.string "owner_type"
    t.bigint "owner_id"
    t.string "processor", null: false
    t.string "processor_id"
    t.boolean "default"
    t.json "data"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "type"
    t.index ["owner_type", "owner_id", "processor"], name: "index_pay_merchants_on_owner_type_and_owner_id_and_processor"
  end

  create_table "pay_payment_methods", force: :cascade do |t|
    t.bigint "customer_id", null: false
    t.string "processor_id", null: false
    t.boolean "default"
    t.string "payment_method_type"
    t.json "data"
    t.string "stripe_account"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "type"
    t.index ["customer_id", "processor_id"], name: "index_pay_payment_methods_on_customer_id_and_processor_id", unique: true
  end

  create_table "pay_subscriptions", force: :cascade do |t|
    t.bigint "customer_id", null: false
    t.string "name", null: false
    t.string "processor_id", null: false
    t.string "processor_plan", null: false
    t.integer "quantity", default: 1, null: false
    t.string "status", null: false
    t.datetime "current_period_start", precision: nil
    t.datetime "current_period_end", precision: nil
    t.datetime "trial_ends_at", precision: nil
    t.datetime "ends_at", precision: nil
    t.boolean "metered"
    t.string "pause_behavior"
    t.datetime "pause_starts_at", precision: nil
    t.datetime "pause_resumes_at", precision: nil
    t.decimal "application_fee_percent", precision: 8, scale: 2
    t.json "metadata"
    t.json "data"
    t.string "stripe_account"
    t.string "payment_method_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "type"
    t.json "object"
    t.index ["customer_id", "processor_id"], name: "index_pay_subscriptions_on_customer_id_and_processor_id", unique: true
    t.index ["metered"], name: "index_pay_subscriptions_on_metered"
    t.index ["pause_starts_at"], name: "index_pay_subscriptions_on_pause_starts_at"
  end

  create_table "pay_webhooks", force: :cascade do |t|
    t.string "processor"
    t.string "event_type"
    t.json "event"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

  create_table "usage_credits_allocations", force: :cascade do |t|
    t.bigint "transaction_id", null: false
    t.bigint "source_transaction_id", null: false
    t.integer "amount", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["source_transaction_id"], name: "index_allocations_on_source_transaction_id"
    t.index ["transaction_id", "source_transaction_id"], name: "index_allocations_on_tx_and_source_tx"
    t.index ["transaction_id"], name: "index_allocations_on_transaction_id"
  end

  create_table "usage_credits_fulfillments", force: :cascade do |t|
    t.bigint "wallet_id", null: false
    t.string "source_type"
    t.bigint "source_id"
    t.integer "credits_last_fulfillment", null: false
    t.string "fulfillment_type", null: false
    t.datetime "last_fulfilled_at"
    t.datetime "next_fulfillment_at"
    t.string "fulfillment_period"
    t.datetime "stops_at"
    t.json "metadata", default: {}, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["fulfillment_type"], name: "index_usage_credits_fulfillments_on_fulfillment_type"
    t.index ["next_fulfillment_at"], name: "index_usage_credits_fulfillments_on_next_fulfillment_at"
    t.index ["source_type", "source_id"], name: "index_usage_credits_fulfillments_on_source"
    t.index ["wallet_id"], name: "index_usage_credits_fulfillments_on_wallet_id"
  end

  create_table "usage_credits_transactions", force: :cascade do |t|
    t.bigint "wallet_id", null: false
    t.integer "amount", null: false
    t.string "category", null: false
    t.datetime "expires_at"
    t.bigint "fulfillment_id"
    t.json "metadata", default: {}, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["category"], name: "index_usage_credits_transactions_on_category"
    t.index ["expires_at", "id"], name: "index_transactions_on_expires_at_and_id"
    t.index ["expires_at"], name: "index_usage_credits_transactions_on_expires_at"
    t.index ["fulfillment_id"], name: "index_usage_credits_transactions_on_fulfillment_id"
    t.index ["wallet_id", "amount"], name: "index_transactions_on_wallet_id_and_amount"
    t.index ["wallet_id"], name: "index_usage_credits_transactions_on_wallet_id"
  end

  create_table "usage_credits_wallets", force: :cascade do |t|
    t.string "owner_type", null: false
    t.bigint "owner_id", null: false
    t.integer "balance", default: 0, null: false
    t.json "metadata", default: {}, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["owner_type", "owner_id"], name: "index_usage_credits_wallets_on_owner"
  end

  create_table "users", force: :cascade do |t|
    t.string "email"
    t.string "name"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

  add_foreign_key "pay_charges", "pay_customers", column: "customer_id"
  add_foreign_key "pay_charges", "pay_subscriptions", column: "subscription_id"
  add_foreign_key "pay_payment_methods", "pay_customers", column: "customer_id"
  add_foreign_key "pay_subscriptions", "pay_customers", column: "customer_id"
  add_foreign_key "usage_credits_allocations", "usage_credits_transactions", column: "source_transaction_id"
  add_foreign_key "usage_credits_allocations", "usage_credits_transactions", column: "transaction_id"
end
