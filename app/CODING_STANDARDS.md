# Coding standards

Two ideas drive this codebase: keep parts **simple** (each does one thing,
composed via plain values), and write **defensive** code that fails loudly on
programming errors. Concretely:

## Simple Made Easy (Rich Hickey)

- One responsibility per type and per function. Do not braid concerns
  (auth ≠ process control ≠ playback ≠ UI).
- Compose via immutable **values** (`struct`, enums, URLs), not shared mutable
  state. Pass data in, return data out.
- Reference types (`class`) only where identity is unavoidable: OS processes,
  windows, players, the HTTP listener.
- Prefer pure functions (e.g. all of `TuyaCrypto`). Side effects live at the
  edges and are named for what they do.
- No global mutable state. Dependencies are injected, not reached for.

## NASA "Power of Ten", adapted to Swift

1. **Simple control flow.** No recursion. No `goto`-like escapes.
2. **Bounded loops.** Every loop has an explicit constant upper bound (retry
   counts, MFA polls, byte scans). Never an unbounded `while true`.
3. **Small functions.** ≤ 60 lines (one screen), one job.
4. **At least two checks per function.** Use `precondition(_:)` for public/API
   contracts (kept in release builds) and `assert(_:)` for internal invariants
   (debug-only) — to catch programming errors at the point they occur.
5. **Handle every error.** Functions that can fail `throw` or return `Result`.
   No empty `catch`. No force-unwrap (`!`) or force-`try`, except immediately
   after an assertion/guard that proves safety.
6. **Smallest scope.** Declare at point of use; `let` over `var`; `private` by
   default.
7. **Values and immutability by default.** See above.
8. **No runtime magic.** No reflection-driven behaviour, no Obj-C swizzling, no
   dynamic dispatch tricks.

## Practical notes

- `precondition` vs `assert`: a caller passing a bad argument is a contract
  violation → `precondition`. An impossible internal state is a bug → `assert`.
- Secrets (password, session tokens) never go to logs. Log identifiers and
  states, not credentials.
