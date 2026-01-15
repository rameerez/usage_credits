## [0.3.0] - 2026-01-15

- Add lifecycle callbacks by @rameerez in https://github.com/rameerez/usage_credits/pull/25
- Fix credit pack fulfillment not working with Pay 10+ (Stripe data in `object` vs `data` in `Pay::Charge`) by @rameerez in https://github.com/rameerez/usage_credits/pull/26

## [0.2.1] - 2026-01-15

- Add custom `create_checkout_session` options (like `success_url`) to credit pack purchases by @yshmarov in https://github.com/rameerez/usage_credits/pull/5

## [0.2.0] - 2025-12-29

- Add Claude Code GitHub Workflow by @rameerez in https://github.com/rameerez/usage_credits/pull/14
- Add test suite by @rameerez in https://github.com/rameerez/usage_credits/pull/15
- Update Pay gem dependency to support versions 8.3 to 9.x by @rameerez in https://github.com/rameerez/usage_credits/pull/16
- Update Pay gem dependency to support version 8.3 to < 10.0 by @kaka-ruto in https://github.com/rameerez/usage_credits/pull/10
- Add Pay version matrix testing with Appraisal by @rameerez in https://github.com/rameerez/usage_credits/pull/17
- Upgrade Pay dependency to support version 10.x by @rameerez in https://github.com/rameerez/usage_credits/pull/18
- Upgrade Pay dependency to support version 11.x by @rameerez in https://github.com/rameerez/usage_credits/pull/19
- Remove payment intent metadata from Subscription checkout session by @cole-robertson in https://github.com/rameerez/usage_credits/pull/2
- Handle subscription plan changes (upgrades & downgrades) by @rameerez in https://github.com/rameerez/usage_credits/pull/20
- Add configurable minimum fulfillment period for dev/test flexibility by @rameerez in https://github.com/rameerez/usage_credits/pull/21
- Add multi-period Stripe price support for subscription plans by @rameerez in https://github.com/rameerez/usage_credits/pull/22
- Fix a bug where very fast fulfillment periods would cause credits not to expire fast enough by @rameerez in https://github.com/rameerez/usage_credits/pull/23
- Fix incomplete fulfillment update on subscription plan upgrade by @rameerez in https://github.com/rameerez/usage_credits/pull/24

## [0.1.1] - 2025-01-14

- Rename `Wallet#subscriptions` to `Wallet.credit_subscriptions` so that it doesn’t override the Pay gem’s own subscriptions association on `User`
- Add non-postgres fallbacks for PostgreSQL-only operations (namely `@>` to access json attributes)
- Add optional `expires_at` to `give_credits` so you can expire any batch of credits at any arbitrary date in the future
- Add Allocation associations to the Wallet model
- Add demo Rails app to showcase the gem features

## [0.1.0] - 2025-01-12

- Initial release
