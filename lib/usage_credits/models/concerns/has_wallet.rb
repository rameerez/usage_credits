# frozen_string_literal: true

module UsageCredits
  # Adds credit wallet functionality to a model
  module HasWallet
    extend ActiveSupport::Concern

    included do
      has_one :credit_wallet,
              class_name: "UsageCredits::Wallet",
              as: :owner,
              dependent: :destroy,
              autosave: true

      after_create :create_credit_wallet, if: :should_create_wallet?

      # More intuitive delegations
      delegate :credits,
               :credit_history,
               :has_enough_credits_to?,
               :spend_credits_on,
               :give_credits,
               to: :credit_wallet,
               allow_nil: true
    end

    # Class methods added to the model
    class_methods do
      def has_credits(**options)
        # Initialize class instance variable instead of class variable
        @credit_options = options

        # Ensure wallet is created by default unless explicitly disabled
        @credit_options[:auto_create] = true if @credit_options[:auto_create].nil?
      end

      def credit_options
        @credit_options ||= { auto_create: true }
      end
    end

    def credit_options
      self.class.credit_options
    end

    private

    def should_create_wallet?
      credit_options[:auto_create] != false
    end

    def create_credit_wallet
      build_credit_wallet(
        balance: credit_options[:initial_balance] || 0,
        low_balance_threshold: credit_options[:low_balance_threshold]
      ).save!
    end
  end
end
