# This migration comes from pay (originally 2)
class AddPayStiColumns < ActiveRecord::Migration[6.0]
  def change
    add_column :pay_customers, :type, :string
    add_column :pay_charges, :type, :string
    add_column :pay_subscriptions, :type, :string

    rename_column :pay_payment_methods, :type, :payment_method_type
    add_column :pay_payment_methods, :type, :string

    add_column :pay_merchants, :type, :string

    Pay::Customer.find_each do |pay_customer|
      pay_customer.update(type: "Pay::#{pay_customer.processor.classify}::Customer")

      # Pay 11.x renamed associations with pay_ prefix for compatibility
      charges_association = pay_customer.respond_to?(:pay_charges) ? :pay_charges : :charges
      subscriptions_association = pay_customer.respond_to?(:pay_subscriptions) ? :pay_subscriptions : :subscriptions
      payment_methods_association = pay_customer.respond_to?(:pay_payment_methods) ? :pay_payment_methods : :payment_methods

      pay_customer.public_send(charges_association).update_all(type: "Pay::#{pay_customer.processor.classify}::Charge")
      pay_customer.public_send(subscriptions_association).update_all(type: "Pay::#{pay_customer.processor.classify}::Subscription")
      pay_customer.public_send(payment_methods_association).update_all(type: "Pay::#{pay_customer.processor.classify}::PaymentMethod")
    end

    Pay::Merchant.find_each do |pay_merchant|
      pay_merchant.update(type: "Pay::#{pay_merchant.processor.classify}::Merchant")
    end
  end
end
