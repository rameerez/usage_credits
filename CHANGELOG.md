## [1.0.0] - Unreleased

`usage_credits` is now built on top of [`wallets`](https://github.com/rameerez/wallets), our append-oriented, multi-asset ledger core. The credits-focused DX you know is unchanged — same `has_credits`, `spend_credits_on`, `give_credits`, packs, subscriptions, and Pay integration — but the expiration-aware allocation ledger, balance math, row-level locking, and transfer machinery now live in a shared, independently tested core.

### Added

- New runtime dependency: `wallets` (`~> 0.3.0`), installed automatically with the gem
- Upgrade generator for existing installs: `rails generate usage_credits:upgrade` creates an in-place, re-runnable migration that preserves all existing ledger data. Before touching the schema it rejects duplicate owner wallets or fulfillment sources, partial polymorphic references, orphaned ledger or Pay sources, invalid ledger amounts/allocations, incompatible key types, reserved-index collisions, and interrupted transfer schemas with actionable diagnostics.
- Wallet-to-wallet credit transfers via the underlying wallets layer (`usage_credits_transfers` table), with expiration-preserving semantics by default
- `UsageCredits::Transfer` model, plus `transfer_in` / `transfer_out` transaction categories

### Changed

- **Schema** (handled by the upgrade migration for existing apps): wallets gain an `asset_code` column (default `"credits"`); one wallet per owner per asset is now enforced with a unique index; `balance` / `amount` / `credits_last_fulfillment` columns widen from `integer` to `bigint`; transactions gain a nullable `transfer_id` reference
- `UsageCredits::Wallet`, `Transaction`, and `Allocation` now subclass the `wallets` core models via its embeddability hooks (same tables as before, prefixed `usage_credits_`)
- Wallet creation now goes through the race-safe, idempotent `create_for_owner!` from the wallets core; an `initial_balance` is recorded as a proper ledger transaction (category `manual_adjustment`, reason `initial_balance`) instead of a bare column write, so initial balances are auditable
- Payment and subscription terms are snapshotted at checkout/fulfillment time, so delayed webhooks, refunds, renewals, and plan changes never depend on mutable initializer configuration.
- Credit-pack fulfillment/refunds and subscription fulfillment are serialized with row locks and database uniqueness constraints; successful callbacks are deferred until the outermost transaction commits.
- Pay fulfillment hooks run only after create/update commits, never after destroy commits; deleting an eligible but unfulfilled processor record cannot mint credits against a dangling source.
- Credit-pack refunds are cumulative, proportional, and idempotent under concurrent webhook delivery. If purchased credits were already spent, the refund records explicit credit debt instead of silently under-refunding; a never-fulfilled purchase cannot create debt.
- Operations evaluate dynamic costs exactly once under the wallet lock, and free operations remain ledger-free while preserving the established callback contract.
- `expire_after` now applies the snapshotted cancellation policy to credits created by that subscription, including after the configured plan is removed; unrelated credits are never shortened.
- Persisted fulfillment cadence is parsed through the same strict duration parser as configuration and is never permitted below one second, preventing malformed metadata or a zero-period retry loop.
- Recurring Pay-backed fulfillment locks and re-checks the subscription before minting, fails closed for dangling Pay sources (including processor-specific STI type names) and unresolved plan transitions, and never awards while the processor subscription is trialing, paused, incomplete, or canceled.
- The locked subscription freshness check canonicalizes processor timestamps to the database column precision. Sub-microsecond values from processor SDKs can no longer make a just-committed callback look stale and silently suppress the initial credit award.
- Subscription lifecycle transactions now exit their blocks locally instead of using method-level `return`, preserving explicit commit semantics across the Rails 7.2-to-8.x behavior change; unrelated subscription updates also skip deferred-resume reconciliation queries.
- Credit-wallet lookup now delegates cold-cache lookup and race recovery to the wallets core's single `create_for_owner!` path instead of querying the same owner/asset association first.
- `transfer_to` and its backwards-compatible `transfer_credits_to` alias now share the complete expiration-policy signature and consistently translate core transfer failures into the `usage_credits` error hierarchy.
- Effective processor pauses use Pay's processor-specific lifecycle predicate rather than raw status (Stripe can remain `"active"` while paused). Plan changes made during a pause are snapshotted without minting, reconciled before the first resumed fulfillment even if an after-commit callback was interrupted, and rejected fail-closed if the persisted terms are inconsistent.
- Fresh and upgrade migrations add row-local ledger constraints and abort before schema changes when legacy rows violate amount, allocation, transfer, wallet, or fulfillment invariants.
- Rails 7.2's transaction callback API is now required to prevent rolled-back ledger events.
- Ruby 3.2 and Rails 7.2.3.1 are the minimum supported runtime versions. Current security-patched Rails dependency releases cannot be installed on Ruby 3.1, and earlier Rails 7.2 patch releases contain known vulnerabilities.
- Pay 11.6.2 is now the minimum supported version. Earlier Pay releases are excluded because [GHSA-mjgf-xj26-9qf9](https://github.com/pay-rails/pay/security/advisories/GHSA-mjgf-xj26-9qf9) permits forged Paddle Billing webhooks through non-constant-time signature comparison.

### Preserved public surface

- The established entry points remain: `credits`, `credit_history`, `give_credits`, `spend_credits_on`, `has_enough_credits_to?`, `estimate_credits_to`, `add_credits`, `deduct_credits`, callbacks, categories, scopes, and the Pay integration.
- Negative balances still floor to zero in `credits` (the wallets core can represent overdrafts, but `usage_credits` keeps its historical contract)
- `usage_credits` stays single-asset (`"credits"`) by design — multi-asset apps can use the `wallets` gem directly, side by side, including in the same app

### Tests

- The suite now contains 813 runs / 2,234 assertions, including adversarial coverage for concurrent fulfillment/refund delivery, stale processor records, processor timestamp precision, processor pauses/resumes, transfer API/error compatibility, cross-gem isolation, destroy callbacks, immutable commercial terms, cancellation expiration, malformed persisted cadence, interrupted upgrades, and database constraints.
- Compatibility coverage includes Ruby 3.2 across both the Rails 7.2 and Rails 8.1 boundaries, Ruby 3.3/3.4/4.0 across Rails 7.2/8.1 and both the Pay 11.6.2 security floor and latest compatible Pay release, plus clean migrations and the full suite on SQLite, PostgreSQL, and MySQL.
- CI audits every supported dependency bundle against the latest `ruby-advisory-db` before release.

### Upgrade instructions

1. Release or install `wallets` 0.3.x first; `usage_credits` 1.0 will not resolve against 0.2.x.
2. Update `usage_credits`, then run `rails generate usage_credits:upgrade`.
3. Review the generated migration and **back up your database** (the migration is not reversible).
4. Run the migration against a production snapshot, resolve every preflight failure, and measure its locking window before deployment. On PostgreSQL, locks acquired across all ledger DDL are held until the whole migration commits.
5. Deploy the gem update and `rails db:migrate` together — the 1.0 models expect the upgraded schema.

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
