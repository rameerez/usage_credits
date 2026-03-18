# frozen_string_literal: true

module UsageCredits
  # Adds credit wallet functionality to a model
  module HasWallet
    extend ActiveSupport::Concern

    included do
      # Filter to the default "credits" asset_code for backwards compatibility
      has_one :credit_wallet,
              -> { where(asset_code: "credits") },
              class_name: "UsageCredits::Wallet",
              as: :owner,
              dependent: :destroy

      alias_method :credits_wallet, :credit_wallet
      alias_method :wallet, :credit_wallet

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

      # Returns all active subscriptions as CreditSubscriptionPlan objects
      def credit_subscriptions
        return [] unless credit_wallet

        credit_wallet.fulfillments
          .where(fulfillment_type: "subscription")
          .active
          .map { |f| UsageCredits.find_subscription_plan_by_processor_id(f.metadata["plan"]) }
          .compact
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
      wallet = original_credit_wallet || UsageCredits::Wallet.find_by(owner: self, asset_code: "credits")
      return wallet if wallet.present?
      return unless should_create_wallet?
      raise "Cannot create wallet for unsaved owner" unless persisted?

      UsageCredits::Wallet.create_for_owner!(
        owner: self,
        asset_code: "credits",
        initial_balance: credit_options[:initial_balance].to_i
      )
    end

    def create_credit_wallet
      ensure_credit_wallet
    end
  end
end
