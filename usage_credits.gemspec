# frozen_string_literal: true

require_relative "lib/usage_credits/version"

Gem::Specification.new do |spec|
  spec.name = "usage_credits"
  spec.version = UsageCredits::VERSION
  spec.authors = ["Javi R"]
  spec.email = ["4920956+rameerez@users.noreply.github.com"]

  spec.summary = "Add a delightful credits system to your Rails app in minutes."
  spec.description = "A Ruby gem that makes it dead simple to add a credits system to your Rails app. Perfect for SaaS and API products that want to implement usage-based pricing. Seamlessly integrates with the pay gem for handling purchases and subscriptions. Define credit operations, sell credit packs, and manage subscription-based credit allowances with a beautiful, intuitive DSL that reads like English."
  spec.homepage = "https://github.com/rameerez/usage_credits"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.1.0"

  spec.metadata["allowed_push_host"] = "https://rubygems.org"
  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = spec.homepage
  spec.metadata["changelog_uri"] = "#{spec.homepage}/blob/main/CHANGELOG.md"
  spec.metadata["rubygems_mfa_required"] = "true"

  # Specify which files should be added to the gem when it is released.
  # The `git ls-files -z` loads the files in the RubyGem that have been added into git.
  gemspec = File.basename(__FILE__)
  spec.files = IO.popen(%w[git ls-files -z], chdir: __dir__, err: IO::NULL) do |ls|
    ls.readlines("\x0", chomp: true).reject do |f|
      (f == gemspec) ||
        f.start_with?(*%w[bin/ test/ spec/ features/ .git .github appveyor Gemfile])
    end
  end
  spec.bindir = "exe"
  spec.executables = spec.files.grep(%r{\Aexe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  spec.add_dependency "pay", "~> 6.0"
  spec.add_dependency "rails", ">= 6.1"

  spec.add_development_dependency "rspec", "~> 3.12"
  spec.add_development_dependency "rubocop", "~> 1.50"
  spec.add_development_dependency "rubocop-performance", "~> 1.17"
  spec.add_development_dependency "rubocop-rails", "~> 2.19"
  spec.add_development_dependency "rubocop-rspec", "~> 2.22"
  spec.add_development_dependency "sqlite3", "~> 1.6"
end
