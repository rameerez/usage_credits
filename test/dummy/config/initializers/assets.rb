# Be sure to restart your server when you modify this file.

# Version of your assets, change this if you want to expire all your assets.
# Rails 7.2 uses Propshaft by default, Rails 8.0+ has different asset handling
if Rails.application.config.respond_to?(:assets)
  Rails.application.config.assets.version = "1.0"

  # Add additional assets to the asset load path.
  # Rails.application.config.assets.paths << Emoji.images_path
end
