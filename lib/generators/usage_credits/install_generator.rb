# frozen_string_literal: true

require "rails/generators/base"
require "rails/generators/active_record"

module UsageCredits
  module Generators
    class InstallGenerator < Rails::Generators::Base
      include ActiveRecord::Generators::Migration

      source_root File.expand_path("templates", __dir__)

      def self.next_migration_number(dir)
        ActiveRecord::Generators::Base.next_migration_number(dir)
      end

      def create_migration_file
        migration_template "create_usage_credits_tables.rb.erb", File.join(db_migrate_path, "create_usage_credits_tables.rb")
      end

      def create_initializer
        destination = "config/initializers/usage_credits.rb"
        if File.exist?(File.expand_path(destination, destination_root))
          # Never clobber a configured app. Thor's interactive conflict prompt
          # is not a safety net in non-TTY runs (scripts, CI, AI agents), and
          # this file is where apps define their whole credits catalog.
          say_status :skip, "#{destination} already exists — keeping your configuration (delete it and re-run to regenerate the template)", :yellow
          return
        end
        template "initializer.rb", destination
      end

      def display_post_install_message
        say "\n🎉 The `usage_credits` gem has been successfully installed!", :green
        say "\nTo complete the setup:"

        say "  1. Run 'rails db:migrate' to create the necessary tables."
        say "     ⚠️  You must run migrations before starting your app!", :yellow

        say "  2. Add 'has_credits' to your User model (or any model that should have credits)."

        say "  3. Define the actions that consume credits in config/initializers/usage_credits.rb"
        say "     ➡️ See README.md for usage examples and detailed configuration options."

        say "  4. 💸 Make sure you have the `pay` gem installed and configured for your chosen payment processor(s) if you want to handle payments and subscriptions (f.ex. for credit refills)"

        say "\nEnjoy your new usage-based credits system! 💳✨\n", :green
      end

      private

      def migration_version
        "[#{ActiveRecord::VERSION::STRING.to_f}]"
      end
    end
  end
end
