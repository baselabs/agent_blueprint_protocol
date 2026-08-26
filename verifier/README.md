# ABP Conformance Verifier

An independent second-language implementation of the Agent Blueprint
Protocol: its own bounded JSON scanner (duplicate rejection, integer
window), its own RFC 8785 canonicalizer (number digits anchored to the
native ECMAScript serializer, member sort by UTF-16 code units),
domain-separated digests, detached-JWS Ed25519 verification through
`node:crypto` with small-order key rejection, and the negotiation,
bounds-algebra, compatibility, and federation semantics. Zero npm
runtime dependencies — `node:` builtins only; Node >= 24 required.

The verifier recomputes every conformance corpus verdict and integrity
check; the release gate requires its report to be byte-identical to
the Elixir escript's over both the repository corpus and the shipped
Hex archive's corpus (see RUNNER.md for the wire formats and exit
codes).

## Run

```bash
node verifier/cli.ts --corpus priv/conformance   # exit 0/1/2; report bytes on stdout
node verifier/self_checks.ts                     # RFC 8785 Appendix B, window matrix,
                                                 # Ed25519 keys, stored JOSE vectors
```

## Distribution

A per-release tarball (`verifier-<version>.tar.gz`) is attached to
each git release tag: this tree plus the release's conformance corpus,
flattened to the tarball root — from the extracted tarball, run
`node cli.ts --corpus conformance`. npm distribution is deferred until
a TypeScript consumer needs dependency-manager distribution.
