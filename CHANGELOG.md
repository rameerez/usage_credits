## [1.0.0] - Unreleased

`usage_credits` is now built on top of [`wallets`](https://github.com/rameerez/wallets), our append-only, multi-asset ledger core. The credits-focused DX you know is unchanged — same `has_credits`, `spend_credits_on`, `give_credits`, packs, subscriptions, and Pay integration — but the FIFO ledger, balance math, row-level locking, and transfer machinery now live in a shared, independently tested core.

### Added

- New runtime dependency: `wallets` (`~> 0.2`), installed automatically with the gem
- Upgrade generator for existing installs: `rails generate usage_credits:upgrade` creates an in-place, re-runnable migration that preserves all existing ledger data. It pre-checks for duplicate owner wallets (possible under pre-1.0's lack of a uniqueness constraint) and aborts with actionable instructions *before* touching the schema if any exist
- Wallet-to-wallet credit transfers via the underlying wallets layer (`usage_credits_transfers` table), with expiration-preserving semantics by default
- `UsageCredits::Transfer` model, plus `transfer_in` / `transfer_out` transaction categories

### Changed

- **Schema** (handled by the upgrade migration for existing apps): wallets gain an `asset_code` column (default `"credits"`); one wallet per owner per asset is now enforced with a unique index; `balance` / `amount` / `credits_last_fulfillment` columns widen from `integer` to `bigint`; transactions gain a nullable `transfer_id` reference
- `UsageCredits::Wallet`, `Transaction`, and `Allocation` now subclass the `wallets` core models via its embeddability hooks (same tables as before, prefixed `usage_credits_`)
- Wallet creation now goes through the race-safe, idempotent `create_for_owner!` from the wallets core; an `initial_balance` is recorded as a proper ledger transaction (category `manual_adjustment`, reason `initial_balance`) instead of a bare column write, so initial balances are auditable

### Unchanged (backwards compatibility)

- The entire public API: `credits`, `credit_history`, `give_credits`, `spend_credits_on`, `has_enough_credits_to?`, `estimate_credits_to`, `add_credits`, `deduct_credits`, callbacks, categories, scopes, and the Pay integration all behave exactly as in 0.5.0
- Negative balances still floor to zero in `credits` (the wallets core can represent overdrafts, but `usage_credits` keeps its historical contract)
- `usage_credits` stays single-asset (`"credits"`) by design — multi-asset apps can use the `wallets` gem directly, side by side, including in the same app

### Upgrade instructions

1. Update the gem, then run `rails generate usage_credits:upgrade`
2. Review the generated migration and **back up your database** (the migration is not reversible)
3. Deploy the gem update and `rails db:migrate` together — the 1.0 models expect the upgraded schema

## [0.5.0] - 2026-03-15

- Add configurable transaction categories via `config.additional_categories` for money-like wallet use cases (marketplaces, fintech) by @rameerez in https://github.com/rameerez/usage_credits/pull/29

## [0.4.0] - 2026-01-16

- Add `balance_before` and `balance_after` to transactions by @rameerez (h/t @yshmarov) in https://github.com/rameerez/usage_credits/pull/27
- Add MySQL support and multi-database CI testing by @rameerez in https://github.com/rameerez/usage_credits/pull/28

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
