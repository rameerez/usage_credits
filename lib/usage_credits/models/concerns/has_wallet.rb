# frozen_string_literal: true

module UsageCredits
  # Adds credit wallet functionality to a model
  module HasWallet
    extend ActiveSupport::Concern

    included do
      has_one :credit_wallet,
              class_name: "UsageCredits::Wallet",
              as: :owner,
              dependent: :destroy

      after_create :create_credit_wallet, if: :should_create_wallet?

      # More intuitive delegations
      delegate :credits,
               :credit_history,
               :has_enough_credits_to?,
               :estimate_credits_to,
               :spend_credits_on,
               :give_credits,
               to: :ensure_credit_wallet,
               allow_nil: false # Never return nil for these methods

      # Fix recursion by properly aliasing the original method
      alias_method :original_credit_wallet, :credit_wallet

      # Then override it
      define_method(:credit_wallet) do
        ensure_credit_wallet
      end
    end

    # Class methods added to the model
    class_methods do
      def has_credits(**options)
        include UsageCredits::HasWallet unless included_modules.include?(UsageCredits::HasWallet)

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

    def ensure_credit_wallet
      return original_credit_wallet if original_credit_wallet.present?
      return unless should_create_wallet?

      if persisted?
        build_credit_wallet(
          balance: credit_options[:initial_balance] || 0
        ).tap(&:save!)
      else
        raise "Cannot create wallet for unsaved owner"
      end
    end

    def create_credit_wallet
      ensure_credit_wallet
    end
  end
end
