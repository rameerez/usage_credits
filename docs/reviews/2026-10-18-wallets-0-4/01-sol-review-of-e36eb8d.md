# Review of usage_credits 1.0.0 on wallets 0.4.0 (Codex Sol, 2026-10-18, at commit e36eb8d, PR #30)

Scope: `git diff dac24e7..e36eb8d`, the move of the 1.0.0 branch from wallets 0.3 to the released 0.4.0 (dependency pin, `ledger_revision`, coexistence dummy schema, inherited behaviour changes, CI through `WALLETS_PATH`), read-only. Verdict: BLOCK; everything below was fixed in commit 639f5dd and re-reviewed (02).

## Blocking

- **Spending still checks stale balances.** [wallet.rb:140](lib/usage_credits/models/wallet.rb:140) reads `credits` and executes the operation block before entering the core’s `mutating_at` context. Under MySQL repeatable read, a concurrent debit can leave this check seeing sufficient funds; the block runs, then the core rejects the debit. A concurrent credit can instead cause a false rejection. Pin the mutation context around the check, block and debit.

- **Fulfillment expiry can conceal a stale snapshot from subsequent commands.** [wallet.rb:224](lib/usage_credits/models/wallet.rb:224) calls `refresh_cached_balance!` without `mutating_at`. It can cache a stale balance and increment the revision without recording the stale-snapshot verdict. Subsequent commands in that transaction see their own revision write matching the locked row and can continue using stale allocation data. The counter increments, but the claimed concurrency protection does not hold. Wrap expiry’s reads and writes in the core mutation context.

## Should fix

- **The schema was not regenerated.** [schema.rb:188](test/dummy/db/schema.rb:188) lacks both `ledger_revision` columns and the entire `wallets_holds` table. Schema-loaded databases therefore fail coexistence operations and the new revision tests. CI’s migration resets conceal this drift.
- **Trilogy handling remains inconsistent.** The coexistence migration correctly uses `/mysql|trilogy/i`, but the usage_credits [install template:135](lib/generators/usage_credits/templates/create_usage_credits_tables.rb.erb:135) and upgrade template still recognize only `mysql`, supplying the JSON defaults the wallets migration deliberately avoids.

## Nits

- The upgrade documentation overstates the missing-revision failure: balance readers query holds but do not check `ledger_revision`; commands check it. Missing the holds table does break balance reads.

## Missing tests

- MySQL read-before-concurrent-write cases for spending and expiry, including **expiry followed by another debit in the same transaction**.
- Rescue-and-commit coverage for operation-block database writes: `spend_credits_on` itself still joins the caller’s transaction; only its debit gets the new savepoint.
- Loading the committed schema and exercising both ledgers. The eight new tests otherwise cover their stated successful paths, six hold-command rejections and fully backed `:preserve` case.

VERDICT: BLOCK

Publication of wallets 0.4.0 alone does not make this safe to release; fix the mutation-context gaps first. The disabled-holds embedding, revision-update paths, holds-table definition, dependency pin and CI release SHA otherwise check out. Release notes must warn about the irreversible usage_credits migration, the separate wallets upgrade for coexistence, unsupported hold keywords, callback timing under `joinable: false`, added insufficient-credit metadata, changed `:preserve` behavior with refund debt, and Pay 11’s receipts 2 requirement when receipts is installed.