# Review of 1.0.1 (Codex Sol, 2026-10-18, at commit 8020366, PR #36)

Scope: `git diff eaae6da..8020366`, the 1.0.1 change (wallets floor `~> 0.4.2` for the rolled-back-instance fix, the `spend_credits_on` regression test, `InsufficientCredits` wording, the CI pin at the v0.4.2 commit), read-only. Verdict: BLOCK only on the version constant, which still read 1.0.0; bumped in 2e606e8 together with the README nit and the wording test.

## Blocking

- [version.rb:4](lib/usage_credits/version.rb:4) still declares `1.0.0`, and the gemspec uses that constant. Bump it before publishing; this HEAD builds a `1.0.0` gem.

## Should fix

None found in the implementation. Both rollback tests retry the same dirty instance without reloading; reading `credits` does not clear it. Against wallets 0.4.1, the retry would encounter Rails’ dirty-record lock refusal. Teardown reloads the owner and cascades destruction through its wallet and ledger.

The regex changes only the leading phrase and preserves diagnostics. `InvalidTransfer` and generic `UsageCredits::Error` still pass core messages through, consistent with the narrower CHANGELOG claim. The changed assertion was the only test pinning “Insufficient balance.” All four CI pins match the peeled v0.4.2 commit. Both CHANGELOG fixes are supported by the code.

## Nits

- [README.md:25](README.md:25) says wallets `0.4.x`; specify `>= 0.4.2, < 0.5`, matching the gemspec and CHANGELOG.

## Missing tests

- No focused assertion covers preserving `; 80 reserved` or leaving a non-leading “Insufficient balance” unchanged.

VERDICT: BLOCK

After the version bump, 1.0.1 appears safe to release once wallets 0.4.2 is on RubyGems, based on this read-only code review.
## Disposition (lead)

Applied in 2e606e8: the version constant is 1.0.1, the README names wallets 0.4.2 or later, and a focused test checks that the credits wording keeps the core's diagnostics ("; 80 reserved") and leaves a non-leading phrase alone.
