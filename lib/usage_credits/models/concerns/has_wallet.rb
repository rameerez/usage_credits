# frozen_string_literal: true

module UsageCredits
  # Adds credit wallet functionality to a model
  module HasWallet
    extend ActiveSupport::Concern

    included do
      # Filter to the default "credits" asset_code for backwards compatibility
      has_one :credit_wallet,
        -> { where(asset_code: UsageCredits::DEFAULT_ASSET_CODE) },
        class_name: "UsageCredits::Wallet",
        as: :owner,
        dependent: :destroy

      # NOTE on the alias dance below: `credits_wallet` and `wallet` are aliased
      # to the raw has_one reader *before* `credit_wallet` is redefined to
      # auto-create missing wallets (see `define_method(:credit_wallet)` further
      # down). So `user.credit_wallet` auto-creates, while `user.wallet` /
      # `user.credits_wallet` just read. This asymmetry is the pre-1.0 contract,
      # kept as-is for backwards compatibility.
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

        # Each class owns an immutable options snapshot. Subclasses inherit it
        # until they explicitly call `has_credits`, without sharing a mutable
        # hash with their parent.
        @credit_options = {auto_create: true}.merge(options.symbolize_keys).freeze
      end

      def credit_options
        return @credit_options if instance_variable_defined?(:@credit_options)
        return superclass.credit_options if superclass.respond_to?(:credit_options)

        {auto_create: true}
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
      credit_wallet_association = association(:credit_wallet)
      cached_wallet = credit_wallet_association.target if credit_wallet_association.loaded?
      return cached_wallet if cached_wallet&.persisted?

      # With auto-creation disabled, retain the ordinary has_one reader and
      # refresh a cached miss so a concurrently-created wallet is still seen.
      # With it enabled, create_for_owner! is the one lookup/creation primitive:
      # it returns an existing row or creates it race-safely. This avoids
      # querying once through the association and then repeating the same
      # owner/asset lookup in create_for_owner! on a cold cache.
      unless should_create_wallet?
        return original_credit_wallet unless credit_wallet_association.loaded?
        return credit_wallet_association.reload.target
      end
      raise "Cannot create wallet for unsaved owner" unless persisted?

      wallet = UsageCredits::Wallet.create_for_owner!(
        owner: self,
        asset_code: UsageCredits::DEFAULT_ASSET_CODE,
        initial_balance: credit_options[:initial_balance]
      )

      self.credit_wallet = wallet
      wallet
    end

    def create_credit_wallet
      ensure_credit_wallet
    end
  end
end
