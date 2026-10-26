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
  spec.required_ruby_version = ">= 3.2.0"

  spec.metadata["allowed_push_host"] = "https://rubygems.org"
  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = "#{spec.homepage}/tree/main"
  spec.metadata["changelog_uri"] = "#{spec.homepage}/blob/main/CHANGELOG.md"
  spec.metadata["rubygems_mfa_required"] = "true"

  spec.files = IO.popen(%w[git ls-files -z], chdir: __dir__, err: IO::NULL) do |ls|
    ls.readlines("\x0", chomp: true).select do |file|
      file.start_with?("lib/", "sig/") ||
        %w[CHANGELOG.md LICENSE.txt README.md].include?(file)
    end
  end
  spec.bindir = "exe"
  spec.executables = spec.files.grep(%r{\Aexe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  # Pay 11.6.2 fixes GHSA-mjgf-xj26-9qf9. Pay 12.0.0 and 12.1.0 accept forged
  # Paddle Billing and Lemon Squeezy webhooks when no signing secret is set
  # (GHSA-5p37-w3f3-55pm, GHSA-6mr3-672j-v5hf); 12.1.1 fixes them.
  spec.add_dependency "pay", ">= 11.6.2", "< 13.0", "!= 12.0.0", "!= 12.1.0"
  spec.add_dependency "rails", ">= 7.2.3.1", "< 9.0"
  spec.add_dependency "wallets", "~> 0.4.2"
end
