# Re-review of the refund fix (Codex Sol, 2026-10-18, at commit 983fcfc, PR #30)

Scope: `git diff 639f5dd..983fcfc`, the answer to review 02: the refund clawback as one wallet command (`UsageCredits::Wallet#deduct_refunded_credits` reads what earlier refunds took through a current read inside the mutation context and debits the rest in the same command), its two-connection test, and the Trilogy test gate. Verdict: PASS; the one nit (the race test's Pay customer and charge outlived the owner's teardown) was applied in the next commit.

## Blocking

None. The refund lookup runs under the lock inside `mutating_at`, using `current_read(..., current_reads?)`; the debit inherits that context. `next` returns nil through `with_lock`. The zero default preserves both direct test callers. The incremental metadata merge preserves the handler’s payload, and nothing outstanding still means no debit and an “already processed” log.

`present?` loads the supplied relation with its locking clause intact, so Ruby fallback filtering also sees current refund rows.

## Should fix

None. Capturing the adapter before stubbing makes both Trilogy result assertions execute on MySQL; the PostgreSQL skip remains appropriate.

## Nits

[Teardown](test/integration/current_reads_test.rb:37) safely destroys the owner, but leaves the new Pay customer and charge orphaned: Pay’s owner association has no dependent destruction. Explicitly clean up that customer in this nontransactional test.

The added CHANGELOG descriptions match the implementation and regression coverage.

## Missing tests

None required for this fix. Rails runs the charge update’s savepoint commit callbacks inside the nonjoinable outer transaction. Consequently, the regression reaches the stale snapshot: on MySQL, 639f5dd would produce refunds of `[-250, -500]`, failing the expected `[-250, -250]`. PostgreSQL exercises the callback path without reproducing MySQL’s stale snapshot.

VERDICT: PASS

Within this re-review’s scope, usage_credits 1.0.0 is now safe to release on wallets 0.4.x. The refund blocker is resolved. Credit-pack fulfillment’s ordinary reads cannot cause duplicate minting because the unique fulfillment-source index guards creation before credits are added. Subscription balance reads outside commands are logging only; grants reconcile inside core commands, and cancellation expiry performs its accounting inside its mutation context. This was a read-only code review; I did not run the suite.