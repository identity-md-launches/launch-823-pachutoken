# LaunchToken ABI

[`LaunchToken.json`](LaunchToken.json) is the compiler-generated JSON ABI array for
`src/LaunchToken.sol:LaunchToken`. It contains the complete constructor, functions,
events, and custom errors. Amounts and allowances are unsigned integers in minor
units: one PACHU is `10^18` minor units. The ABI is generated with Solidity 0.8.26
and the settings in `foundry.toml`.

Regenerate from the repository root after any contract change:

```sh
forge build
forge inspect src/LaunchToken.sol:LaunchToken abi --json > docs/abi/LaunchToken.json
```

## Constructor and functions

The nonpayable constructor has no arguments. It mints exactly `10^27` minor units
to its caller and emits a `Transfer` from the zero address. When launched through
ProjectFactory, the factory is that caller. No initializer is needed or available.

| Signature | Mutability | Result / behavior |
| --- | --- | --- |
| `name()` | view | `string`, always `Pachu` |
| `symbol()` | view | `string`, always `PACHU` |
| `decimals()` | view | `uint8`, always `18` |
| `totalSupply()` | view | `uint256`, always `10^27` |
| `balanceOf(address)` | view | `uint256`, holder's balance; zero for unused addresses |
| `allowance(address,address)` | view | `uint256`, owner-to-spender allowance |
| `transfer(address,uint256)` | nonpayable | `bool`, moves caller's funds to a nonzero recipient |
| `approve(address,uint256)` | nonpayable | `bool`, replaces caller's allowance for a nonzero spender |
| `transferFrom(address,address,uint256)` | nonpayable | `bool`, spends caller's allowance from the owner and moves funds to a nonzero recipient |

State-changing functions return `true` on success and revert on failure. Transfers
do not call recipients. Zero-value transfers are supported; self-transfers do not
change balances. `transferFrom` to the same owner still consumes a finite
allowance. Even a holder calling `transferFrom` on itself needs allowance; use
`transfer` for ordinary holder-initiated movement. Unlimited approval
(`2^256 - 1`) is supported by the standard implementation and remains unchanged
when spent. It is a permission to spend all available and future funds; clients
should request only the allowance needed.

No permit, burn, mint, owner, upgrade, pause, fee, fallback, or receive entry point
is exposed. Unknown selectors and ordinary ETH payments revert. No payable ABI
entry exists.

## Events

| Signature | Indexed fields | Meaning |
| --- | --- | --- |
| `Transfer(address from,address to,uint256 value)` | `from`, `to` | Initial mint or successful transfer, including zero and self transfers |
| `Approval(address owner,address spender,uint256 value)` | `owner`, `spender` | Successful `approve`, including replacement and revocation |

In this OpenZeppelin version, `transferFrom` updates a finite allowance without
emitting `Approval`. Clients must query `allowance` for current permission rather
than reconstructing it from Approval events alone. It does emit `Transfer`.

## Custom errors

| Error | Meaning |
| --- | --- |
| `ERC20InsufficientBalance(address sender,uint256 balance,uint256 needed)` | Requested transfer exceeds the sender's balance |
| `ERC20InvalidSender(address sender)` | Invalid transfer source (zero address) |
| `ERC20InvalidReceiver(address receiver)` | Invalid transfer recipient (zero address) |
| `ERC20InsufficientAllowance(address spender,uint256 allowance,uint256 needed)` | Requested delegated transfer exceeds the caller's allowance |
| `ERC20InvalidApprover(address approver)` | Invalid allowance owner (zero address) |
| `ERC20InvalidSpender(address spender)` | Invalid approval spender (zero address) |

Validation order can affect the first error: `transferFrom` checks/spends allowance
before checking balances and recipient validity. Any subsequent revert rolls
back that allowance change and all balances. Error arguments expose the values at
failure, not a partial successful transfer.
