# ADR: the supported OTP set

## Decision

The supported OTP set is 27/28/29, exercised as: Elixir 1.19 on OTP 28,
and Elixir 1.20 on every supported major. OTP 26 has 1.19-era builds but
sits outside the supported matrix; no Elixir 1.20 build exists for it,
and the 1.19 lane targets that line's newest supported major.

## Consequences

- A foreign-toolchain checkout refuses at the first Mix task (before
  compilation) with a message naming the running major, the Elixir
  version, and the code root, so no shared build state is ever written
  by an unsupported toolchain.
