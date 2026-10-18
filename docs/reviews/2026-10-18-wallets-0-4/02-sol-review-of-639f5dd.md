# Re-review of the fixes (Codex Sol, 2026-10-18, at commit 639f5dd, PR #30)

Scope: `git diff e36eb8d..639f5dd`, the answer to review 01 (`spend_credits_on`, cancellation expiry and the refund debit inside the core's mutation context and their own savepoints; regenerated dummy schema with a drift test and a CI step; Trilogy as MySQL in the migrations and the Pay charge lookups; two-connection race tests). Verdict: BLOCK on one remaining stale read, the refund amount; fixed in commit 983fcfc and re-reviewed (03).

## Blocking

- **Refund amounts still use stale ledger reads.** [handle_refund!](lib/usage_credits/models/concerns/pay_charge_extension.rb:358) locks the wallet, but `credits_previously_refunded` uses ordinary snapshot reads before the debit enters `mutating_at`. In a MySQL `transaction(joinable: false)`, Pay’s savepoint commit callback can run inside an already stale transaction. If another connection refunded 250 of 1,000 credits, a subsequent cumulative 500-credit refund can deduct 500 instead of the remaining 250. The debit’s mutation context starts too late to correct that amount. Make the cumulative lookup a current read within the wallet mutation command.

## Should fix

- **The Trilogy test never checks its answers on MySQL.** It stubs `adapter_name` to `"Trilogy"`, then [tests that stubbed value against `/mysql/i`](test/models/concerns/pay_charge_extension_test.rb:837). Both result assertions are unreachable. Capture the actual adapter before stubbing; retain the PostgreSQL skip.

## Nits

None.

## Missing tests

- Add a two-connection MySQL refund regression with a pre-existing snapshot, including the `joinable: false` callback path. Assert that only the outstanding cumulative delta is deducted.
- After correcting the adapter gate, exercise both Trilogy lookup answers on MySQL.

VERDICT: BLOCK

The original spending and expiry blockers are fixed: locking, pinned context, nested debit behavior, savepoints, and explicit threshold balances are sound. The rollback tests support the documented database guarantees, and the schema and migration-template checks address the earlier gaps. Release on wallets 0.4.x should still wait for the refund amount fix and its regression test. This was a read-only review; I did not run the suite.