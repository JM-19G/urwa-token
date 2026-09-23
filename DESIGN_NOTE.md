# Design Note — Scoped uRWA (ERC-7943) Implementation

## Scope
Implements a scoped-down subset of [ERC-7943](https://eips.ethereum.org/EIPS/eip-7943)
(uRWA — Universal RWA Interface) on top of a standard ERC-20 (OpenZeppelin v5.0.2).

In scope: allow-list based transfer validation, address-level freeze, admin-only
forced transfer, and events for freeze/unfreeze/forced transfer/rejected transfer.
Out of scope (per assignment): identity/KYC integration, multi-jurisdiction logic,
upgradeability, and the spec's *partial-amount* freezing (`setFrozenTokens(account, amount)`) —
this implementation freezes an address as a whole (`setFrozen(account, bool)`).

## Spec mapping
| Function/Event in this contract | Spec section |
|---|---|
| `canSend`, `canReceive` | [canSend/canReceive/canTransfer/getFrozenTokens](https://eips.ethereum.org/EIPS/eip-7943#cansend-canreceive-cantransfer-and-getfrozentokens) — account-level eligibility checks, non-reverting |
| `canTransfer` | same section — transfer-level check, MUST perform `canSend(from)` + `canReceive(to)` |
| `forcedTransfer` | [forcedTransfer](https://eips.ethereum.org/EIPS/eip-7943#forcedtransfer) — admin-restricted, emits base `Transfer` + `ForcedTransfer`, bypasses compliance checks (single-party permissioned context) |
| `setFrozen` / `Frozen` event | [setFrozenTokens](https://eips.ethereum.org/EIPS/eip-7943#setfrozentokens) — admin-restricted, must emit `Frozen` |
| `TransferRejected` | not in the spec verbatim; added to satisfy the assignment's "rejected transfer" event requirement (see decision #2 below) |

## Hardest design decisions

**1. Boolean freeze instead of partial-amount freeze.**
The real spec freezes a specific *amount*, allowing partial freezing above an
account's balance (e.g. "freeze future incoming funds too"). The assignment scope
asked for a simpler "freeze an address so it cannot send" — a binary switch. I kept
the real spec's naming pattern (`setFrozen`/`Frozen`) but simplified the type from
`uint256 amount` to `bool status`, since implementing partial-amount freezing
correctly (with unfrozen-balance math on every transfer) was explicitly out of scope
and added real complexity for no benefit at this scope.

**2. Rejected transfers can't emit a surviving event if the function reverts.**
This is the core EVM constraint that shaped the whole transfer path. If a call
reverts, every log/event emitted *within that call* is discarded along with all
state changes — there's no way to revert a transfer and still have a `TransferRejected`
event persist on-chain. Two options existed: (a) don't revert — have `transfer`/
`transferFrom` return `false` and emit the event instead, or (b) accept that a
rejected-transfer event can never be observed and drop the requirement. I chose (a):
the base ERC-20 standard only requires `Transfer` + `true` on *success*, so returning
`false` on failure is spec-legal, if less common than OpenZeppelin's usual
always-revert pattern. This is the one place my implementation departs furthest from
"how ERC-20 normally behaves," so it's the first thing I'd expect to be asked about
in the live defense.

**3. `forcedTransfer` intentionally bypasses `canTransfer`/frozen checks.**
The spec explicitly allows this in "single-party permissioned contexts" (a single
admin/owner model, which is what this scope uses) — see the forcedTransfer section.
This means an admin can seize tokens from a frozen address, or send them to a
non-allowlisted recovery address, without those checks blocking the seizure. That's
correct per spec, but worth being explicit about since it looks like a bypassed
security check if you don't know it's intentional.

## AI use disclosure
Used Claude to help install and configure the WSL environment, fetch and
summarize the actual EIP-7943 specification text, scaffold the project, and generate
an initial draft of the contract and test suite. I reviewed the spec mapping table
above against the real EIP text and the scope decisions myself before accepting them.

Two things needed fixing from the AI's first output:
1. `emit URWA20.TransferRejected(...)` — this qualified-event syntax requires
   Solidity 0.8.22+, but the project is pinned to 0.8.20 per the assignment rules.
   Fixed by importing/declaring the event directly in the test file instead.
2. A duplicate `contract URWA20Test is Test { ... }` block got introduced during an
   edit and broke compilation with a vague parser error. Fixed by removing the
   duplicate block manually.

