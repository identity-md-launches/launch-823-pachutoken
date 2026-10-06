# Pachu (PACHU) contracts

Pachu is the AI agent company described in the approved workflow. This repository
delivers its fixed-supply launch token, tests, vendored dependencies, and ABI.
The intended release network is **Ethereum mainnet, chain ID 1**.

Status: contract implementation and local verification are complete. No mainnet
deployment, deployed address, verified pool, published repository, or IPFS site is
claimed by this contribution. The separate manifest and independent review stages
precede service-managed publication, attestation, admission, deployment, and the
frontend build.

## Token behavior

`src/LaunchToken.sol:LaunchToken` inherits the vendored OpenZeppelin Contracts
v5.0.2 ERC-20 implementation without overriding transfers or allowances.

| Property | Value |
| --- | --- |
| Name / symbol | Pachu / PACHU |
| Decimals | 18 |
| Fixed supply | 1,000,000,000 PACHU = 1,000,000,000,000,000,000,000,000,000 minor units (`10^27`) |
| Constructor | No arguments, nonpayable |
| Initial recipient | The entire supply goes to `msg.sender`, which is ProjectFactory during launch |
| Further issuance / burning | No externally accessible mint or burn functions |
| Administration | No owner, roles, pause, blocklist, fees, upgrade, or rescue functions |
| Transfers | Exact requested amounts; no tax, external calls, or recipient callbacks |

This matches the approved token requirements without exceptions. The constructor
performs the only mint. The factory is the initial holder and gains no special
authority over the token. Application contracts are unnecessary for this brief;
the project application-contract list is empty. There is no initializer or
contributor deployment script.

Successful `transfer`, `approve`, and `transferFrom` return `true`; failures revert
with ERC-6093 custom errors. Nonzero recipients can receive zero-value transfers.
Self-transfers preserve balances. Zero recipients are rejected even for amount
zero. Finite allowances decrease when spent; `uint256.max` means an unlimited
allowance and does not decrease. Standard ERC-20 approval replacement semantics
apply: callers should revoke an existing allowance before changing it and verify
the resulting allowance; revocation cannot undo already executed spending.

The token accepts no ordinary ETH payments. ETH forcibly sent to it, tokens sent
to the token's own address, and unrelated assets sent there have no recovery
mechanism. Recipient contracts receive no notification and must be able to manage
their own tokens. No oracle, randomness, signature processing, custody protocol,
or ongoing maintenance transaction is needed by this token.

## Build and verify

Install Foundry and make Solidity **0.8.26** available to Foundry. All Solidity
library and test dependencies are already vendored as ordinary source files;
there are no submodules or package installation steps. See
[dependency versions and licenses](docs/DEPENDENCIES.md).

```sh
forge build
forge test
forge fmt --check
```

`foundry.toml` pins Solidity 0.8.26, EVM `paris`, optimizer enabled with 200 runs,
and `bytecode_hash = "none"`. FFI and filesystem cheatcode access are disabled.
The compiler is pinned by version, with no compiler binary in the repository.
Offline verification works once the verifier-provided compiler is installed.

Tests use no environment variables, forks, RPC endpoints, files, or shared
external state. Each test starts from its own deployment and can run in parallel.
The default suite contains 30 unit/fuzz tests and one stateful invariant:

- Initial mint, metadata, CREATE2 prediction, factory custody, and simulated
  allocation transfers of the requested 88% / 2% / 2% / 8% split.
- Events, full-supply and zero-value transfers, self-transfers, allowance
  isolation, finite/unlimited approvals, revocation, and repeated spending.
- Insufficient balance or allowance, zero recipient/spender, atomic rollback on
  failed delegated transfers, rejected ETH, and rejected administrative selectors.
- No recipient callbacks, bounded runtime, and no DELEGATECALL, CALLCODE, or
  SELFDESTRUCT instructions (the scan skips PUSH data).
- Three fuzz properties at 512 cases each, plus 128 invariant sequences of
  64 calls checking supply, balances, and allowances against an independent model
  of four holders, including self-transfers and unlimited approvals.

The test-only factory probe and distribution simulation verify token compatibility;
they do not test the production ProjectFactory, distributor, or pool. The supplied
protected tests are verifier-owned inputs, not part of the delivered test tree.
The local tests exercise their token requirements without depending on verifier
environment variables. These results are not an independent security audit.
Slither and Mythril were not run. Independent source and manifest review remains
the next contributor stage.

## Deployment and manifest handoff

The separate manifest assignment writes `launch.json`; this source contribution
does not generate it. Use these approved parameters when describing the accepted
source:

| Parameter | Required value |
| --- | --- |
| Kind | `evm_project` |
| Network | Ethereum mainnet, chain ID `1` |
| Launch token | `LaunchToken`, source `src/LaunchToken.sol`, decimals `18` |
| Token constructor arguments / value | None / zero ETH |
| Application contracts | Empty list (`[]`) |
| Pool pair currency | Native ETH, `0x0000000000000000000000000000000000000000` |
| Pool allocation | 88% of total supply (8,800 basis points) |
| Manifest pool fee | `3000` (admission value; not the live trading fee) |
| Tick spacing | `60` |
| Manifest initial price | `"79228162514264337593543950336"` (`sqrtPriceX96`, legacy-policy value) |

ProjectFactory performs distribution outside this token:

| Destination | Supply share | PACHU |
| --- | --- | --- |
| Launch pool (requester's allocation) | 88% | 880,000,000 |
| Requester's wallet (remainder of their 90%) | 2% | 20,000,000 |
| Accepted-work contributor wallets, equally | 2% | 20,000,000 |
| Paired seats connected at admission, one share per seat | 8% | 80,000,000 |

The requester chose 88%, overriding the protocol's default 80% pool allocation.
The token does not itself split, retain, or forward these allocations. The factory
supplies the protocol distributor, liquidity setup, and PoolInitializationGuard;
none is implemented here or listed as a project application contract. The guard
restricts initialization only and has no swap callbacks or control over token
transfers.

The factory seeds liquidity with the launch token only. Services derive the
effective opening price from the pinned policy's cap for native ETH (10 ETH where
that policy names it), not from the legacy manifest price. Live trading fees come
from the target chain's LaunchFees configuration: the supplied protocol guidance
describes a default 1.25%, split into 1% for the launch-paying wallet and 0.25% for
IMD, claimable by anyone for those recipients. Services must confirm the admitted
configuration and report the actual fee. The token never charges these fees, and
the site must not present the pool as a 0.3% pool based on manifest fee `3000`.

## Operational responsibilities and assumptions

- The manifest author describes the accepted source and these parameters.
  Independent review inspects both source and the concrete manifest, including
  constructor arguments and any authorization conflicts. Policy and signed
  artifact linkage are provided and checked by services.
- Services select the canonical mainnet factory and policy, publish complete
  source, attest and admit the artifacts, deploy with zero constructor value,
  perform the factory distribution, and verify source on the explorer. No chain
  addresses or privileged wallets have been invented or hard-coded here.
- There is no on-chain chain-ID restriction in this ordinary ERC-20. Services
  enforce mainnet-only deployment. No wallet key or transaction broadcast is
  needed for this assignment, and none is included.
- Services must hand off the verified token address, exact deployed `poolKey`,
  pool details, actual fees, explorer links, and public repository URL. These
  values are unresolved until deployment; the frontend must use that handoff.
- The later frontend assignment presents the AI agent, its purpose and approved
  identity, metadata and truthful release status. It uses the approved motion
  asset at
  `https://d3u0tzju9qaucj.cloudfront.net/234da064-93ed-416b-92bf-1844ab071271/11322e47-5f36-4aab-92d4-76c089d6d64f.mp4`.
  It displays the connected wallet, PACHU balance, verified token/pool details,
  trade and explorer links, fails closed on networks other than mainnet, and is
  published to IPFS after deployment. These downstream outcomes are not claimed
  by the contract stage.

The token is immutable after deployment, including if a bug is later found.
Testing relies on the pinned compiler and vendored library; launch economics and
liquidity custody also rely on the protocol contracts and admitted policy, which
are outside this repository's implementation. No independent reviewer findings
or service outcomes are represented as completed here.

See [ABI documentation](docs/abi/README.md) and the generated
[LaunchToken ABI](docs/abi/LaunchToken.json).
