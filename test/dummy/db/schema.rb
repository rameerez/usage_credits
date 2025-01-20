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

ActiveRecord::Schema[8.0].define(version: 2025_01_20_011957) do
  create_table "usage_credits_transactions", force: :cascade do |t|
    t.bigint "wallet_id", null: false
    t.string "source_type"
    t.bigint "source_id"
    t.integer "amount", null: false
    t.string "category", null: false
    t.datetime "expires_at"
    t.json "metadata", default: {}, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["category"], name: "index_usage_credits_transactions_on_category"
    t.index ["expires_at"], name: "index_usage_credits_transactions_on_expires_at"
    t.index ["source_type", "source_id"], name: "index_usage_credits_transactions_on_source"
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
end
