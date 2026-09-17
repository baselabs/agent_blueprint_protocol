# ADR: the supported OTP set

Status: accepted (2026-09-16).

## Context

The declared Elixir requirement is a supported range (`~> 1.19`), not a
pin: Mix refuses any Elixir outside the range at compile. Nothing,
however, refused an Erlang/OTP major — a foreign-toolchain checkout
compiled silently, and mixing toolchains poisoned shared build and PLT
state into phantom errors and hour-long rebuilds.

The supported set is discovered, never assumed: an OTP major enters only
with real precompiled builds for the declared Elixir line. Probed
2026-09-16 against the official Elixir build list and the official Docker
images: the Elixir 1.19 line ships precompiled otp-26, otp-27, and otp-28
builds; the Elixir 1.20 line ships otp-27, otp-28, and otp-29 builds.

## Decision

The supported OTP set is 27/28/29, exercised as: Elixir 1.19 on OTP 28,
and Elixir 1.20 on every supported major. OTP 26 has 1.19-era builds but
sits outside the supported matrix — no Elixir 1.20 build exists for it,
and the 1.19 lane targets that line's newest supported major.

Enforcement lives in the repository, in code, before anything compiles:
`config/config.exs` raises on any OTP major outside the set. The config
directory is deliberately NOT shipped in the Hex archive — the assert
governs development and CI, not package consumers, whose supported floor
is the Elixir range carried by mix.exs.

Lockstep rule: the mix.exs Elixir range, the config supported-OTP set,
`.tool-versions`, and the CI Elixir/OTP lanes move together in ONE
commit. A lane outside the set, or a supported major without a lane, is
a defect.

## Consequences

- A foreign-toolchain checkout refuses at the first Mix task — before
  compilation — with a message naming the running major, the Elixir
  version, and the code root, so no shared build state is ever written
  by an unsupported toolchain.
- Toolchain and major-dependency changes are followed by a purge of
  `_build` (which holds the PLTs) and exactly one rebuild on the final
  dependency set.
- When the declared Elixir line moves, the build list is re-probed and
  the quadruple is updated in one commit; discovery is repeated, never
  inherited.
- The dev lane (`.tool-versions`) pins what maintainers actually run;
  CI's full battery runs on that pin and the tests plus conformance
  corpus on every lane of the matrix.
