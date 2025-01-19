module UsageCredits
  module Generators
    class InstallGenerator < Rails::Generators::Base
      source_root File.expand_path("templates", __dir__)

      def create_initializer
        template "initializer.rb", "config/initializers/usage_credits.rb"
      end

      def install_migrations
        rake "usage_credits:install:migrations"
      end

      def inject_user_model
        model_file = "app/models/user.rb"
        if File.exist?(model_file)
          inject_into_file model_file, after: "class User < ApplicationRecord\n" do
            "  has_credits\n"
          end
        end
      end

      def show_post_install_message
        readme "README"
      end
    end
  end
end
