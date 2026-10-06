# Pachu contract tests

The suite tests the accepted `src/LaunchToken.sol` and its vendored ERC-20 implementation.
It requires no network, forks, environment variables, extra dependencies, or token-storage overrides.

| File | Coverage |
| --- | --- |
| `LaunchToken.t.sol` | Deployment, fixed supply and metadata, factory compatibility, exact transfers, events, authorization, rollback, nonpayable construction, and forbidden administrative selectors/opcodes. Administrative probes use correctly encoded arguments. |
| `LaunchToken.adversarial.t.sol` | Finite/unlimited approval transitions, revocation after refund, maximum amounts, failed-spend retries, approval isolation and replacement, address aliases, delegated round trips, split versus single spends, and ETH rejection on all ERC-20 entrypoints. Five fuzz properties run 1,000 cases each. |
| `LaunchToken.invariant.t.sol` | Four actors interleave transfers, approvals, delegated spends, revocations, deliberate failures, and full-balance round trips. A deterministic mixed sequence also pins successful and rejected operations. |

The invariant runner executes 256 sequences of 96 handler calls. It checks the fixed
`10^27` supply, the sum of all actor balances, every actor's balance and pairwise allowance
against independently maintained ghosts, and zero balances at unused addresses. Amounts
are bounded using the model, with explicit zero, one, maximum finite and unlimited approvals.
Expected failures must produce the correct custom error; any unexpected handler revert
fails the campaign. Failed operations leave the ghosts unchanged, and round trips must
restore balances without changing approvals. Only the nine action selectors are targeted.

Run from the repository root, keeping generated artifacts in disposable scratch space:

```sh
forge build --offline --out test/scratch/out --cache-path test/scratch/cache
forge test --offline --out test/scratch/out --cache-path test/scratch/cache
```

The factory probe and allocation test simulate the token-facing launch calls. They do not
verify the external ProjectFactory, pool, policy, manifest, deployment services, or frontend.
No reproducible contract defect was found by this contribution; passing tests do not replace
the independent source and manifest review.
