# frozen_string_literal: true

require_relative "lib/usage_credits/version"

Gem::Specification.new do |spec|
  spec.name = "usage_credits"
  spec.version = UsageCredits::VERSION
  spec.authors = ["rameerez"]
  spec.email = ["rubygems@rameerez.com"]

  spec.summary = "Add usage-based credits to your Rails app."
  spec.description = "Add a usage-based credit system to your Rails app, easily. Let users buy and spend credits on usage-based actions. Refill Stripe subscriptions with credits, sell one-time booster credit packs, implement PAYG (pay-as-you-go) billing, award free credits as bonuses, manage prepaid credits / tokens. Your users will have wallet balances that they can spend on features, API calls, or other usage-based actions. Perfect for SaaS, AI apps, games, and API products with metered pricing / billing."
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

  spec.add_dependency "pay", ">= 8.3", "< 12.0"
  spec.add_dependency "rails", ">= 6.1"
end
