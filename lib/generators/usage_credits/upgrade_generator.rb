# frozen_string_literal: true

require "rails/generators/base"
require "rails/generators/active_record"

module UsageCredits
  module Generators
    class UpgradeGenerator < Rails::Generators::Base
      include ActiveRecord::Generators::Migration

      source_root File.expand_path("templates", __dir__)

      def self.next_migration_number(dir)
        ActiveRecord::Generators::Base.next_migration_number(dir)
      end

      def create_migration_file
        migration_template "upgrade_usage_credits_to_wallets_core.rb.erb", File.join(db_migrate_path, "upgrade_usage_credits_to_wallets_core.rb")
      end

      def display_post_upgrade_message
        say "\nUsageCredits 1.0 upgrade migration has been generated!", :green
        say "\nThis migration will:"
        say "  - Add 'asset_code' column to wallets (default: 'credits')"
        say "  - Change integer columns to bigint for larger balance support"
        say "  - Create 'usage_credits_transfers' table for wallet transfers"
        say "  - Add 'transfer_id' column to transactions"
        say "  - Upgrade pre-1.0 installs to the wallets-backed ledger core"
        say "\nTo complete the upgrade:"
        say "  1. Review the migration file in db/migrate/"
        say "  2. Run 'rails db:migrate'"
        say "\n"
      end

      private

      def migration_version
        "[#{ActiveRecord::VERSION::STRING.to_f}]"
      end
    end
  end
end
