# Review of PR #39, no credit grant can vanish through a return out of a transaction block (Codex Sol, 2026-10-18, through commit e35d800)

Scope: `git diff origin/main..e35d800`, the answer to issue #31 / PR #32 on 1.0.1: the audit of every `transaction`, `with_lock` and wallet command block in `lib/` (no non-local exit left), the test documenting that Rails >= 7.2.3.1 commits a block left by `return`, `break` or `throw`, the persistence test for `add_credits`/`give_credits`, the README note on leaving the `spend_credits_on` block, the CHANGELOG entry crediting the reporter; the `Rails/TransactionExitStatement` cop deliberately not added. Verdict: PASS, nothing to apply.

## Blocking

None. Read `within_new_transaction` in installed ActiveRecord 8.1.4, the Rails 7.2 bundle’s 7.2.4, and minimum 7.2.3.1: normal non-local exits commit. The tests and CHANGELOG describe this correctly.

## Should fix

None. Auditing `lib/` found no missed lexical `return`/`break`/`throw` in the targeted blocks. Existing `next` statements exit the intended blocks. No production code changes, so return values, writes, and callbacks remain unchanged. The added README guidance is accurate.

## Nits

None. Agree with omitting `Rails/TransactionExitStatement`: its implementation explicitly skips Rails >= 7.2.

## Missing tests

None required. Persistence assertions query ledger rows and a fresh wallet instance. Integration tests disable fixture transactions and assert zero open transactions, exposing actual commit behavior.

Syntax and diff checks passed; runtime tests were not run during this read-only review. Reviewed through `e35d800`.

VERDICT: PASS

This change is safe to ship in 1.1.0.