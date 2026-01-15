# frozen_string_literal: true

# Migration to add the `object` column introduced in Pay 10
# This column stores the full Stripe/processor response object
class AddObjectToPayModels < ActiveRecord::Migration[6.0]
  def change
    # Only add columns if they don't already exist (for idempotency)
    unless column_exists?(:pay_charges, :object)
      add_column :pay_charges, :object, :json
    end
    unless column_exists?(:pay_customers, :object)
      add_column :pay_customers, :object, :json
    end
    unless column_exists?(:pay_subscriptions, :object)
      add_column :pay_subscriptions, :object, :json
    end
  end
end
