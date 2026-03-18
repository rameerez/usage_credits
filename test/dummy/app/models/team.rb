# frozen_string_literal: true

# Model for testing coexistence of wallets and usage_credits gems
# This model uses has_wallets directly from the wallets gem,
# while User model uses has_credits from usage_credits gem.
class Team < ApplicationRecord
  include Wallets::HasWallets

  has_wallets default_asset: :points
end
