# Review of PR #35, subscription plans take their Stripe prices from pricing_plans (Codex Sol, 2026-10-18, at commit 54c94f4 rebased on 1.0.1)

Scope: the owner's PR #35 rebased onto the 1.0.1 main, read-only. Verdict: BLOCK on one point that predates the PR (an exception inside a Pay `after_commit` callback loses the subscription transition on webhook replay), filed as issue #38 instead of holding the PR; the should-fix (README qualification of pricing_plans price keys), the nit (boot-warning wording) and two of the missing tests (`processor_plan :stripe` before `pricing_plan`; single-price checkout without a period) were applied in the next revision of the commit (b88d57b). The "43 additional lines for the wallets CI override" were the stale rebase base, gone after rebasing onto the post-#37 main.

## Blocking

- **Lazy errors can permanently lose subscription transitions.** If a link becomes unresolved after boot, lookup can raise during an `after_commit` callback. Pay 11.8 propagates the error and retains the webhook, but the subscription update is already committed. After fixing the link, replaying unchanged Stripe data loses the `saved_change_to_*?` flags used by [plan changes and cancellations](lib/usage_credits/models/concerns/pay_subscription_extension.rb:153). An existing fulfillment can retain its old plan, causing recurring fulfillment to reject the unreconciled transition; cancellation credit expiration can also be skipped. Add reconciliation that survives webhook replay.

## Should fix

- **Qualify the arbitrary-key documentation.** The stand-in matches real `pricing_plans` at `f86a7e7`, including `{id: "x"}` storage. However, local revision `65f2fc6` [rejects keys outside its supported intervals and `:id`](pricing_plans: lib/pricing_plans/plan.rb:818). The [README’s arbitrary-key and grandfathered-price guidance](README.md:527) needs a compatible-version qualification or coordinated support.

## Nits

- The [boot warning](lib/usage_credits/configuration.rb:315) incorrectly says the plan will never refill when it still has a matching Paddle ID.
- Rebase scope: one owner-authored commit, eight files, **+584/−2**; includes 43 additional lines for the wallets CI override. No unrelated runtime removal found.

## Missing tests

- Link failure after boot, followed by repair and webhook replay: plan changes, cancellation, renewal, and paused changes.
- Actual engine boot and credential-free precompile; existing tests invoke validation directly.
- `processor_plan :stripe` before `pricing_plan`, plus single-price checkout without a period.
- Automated integration with the real gem; the stand-in suite skips when it is loaded.

Static review found fresh resolution throughout the price accessors, correct declaration-order exclusivity, Paddle combination, blank-value filtering, and validation after normal application initializers.

VERDICT: BLOCK

This needs replay-safe lifecycle recovery before it is safe to ship in 1.1.0.
## Disposition (lead)

The blocking finding describes the Pay subscription extension as it stands on 1.0.1: any exception inside its `after_commit` callbacks, not only a failed pricing_plans link, loses the `saved_change_to_*?` flags on replay. Boot validation keeps configuration errors out of that path, which is the PR's design ("fails loudly"), so the runtime scenario needs a registry that changes after boot, which production does not do. Tracked in issue #38 as reconciliation work for the extension. Not applied: engine-boot and credential-free precompile tests, and an automated integration with the real gem (the stand-in suite skips when the gem is loaded; Agent C ran a scratch boot against pricing_plans 0.7.0 and its unreleased branch, 11 checks passing).
