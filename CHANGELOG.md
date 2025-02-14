## [0.1.1] - 2025-01-14

- Rename `Wallet#subscriptions` to `Wallet.credit_subscriptions` so that it doesn’t override the Pay gem’s own subscriptions association on `User`
- Add non-postgres fallbacks for PostgreSQL-only operations (namely `@>` to access json attributes)
- Add optional `expires_at` to `give_credits` so you can expire any batch of credits at any arbitrary date in the future
- Add Allocation associations to the Wallet model
- Add demo Rails app to showcase the gem features

## [0.1.0] - 2025-01-12

- Initial release
