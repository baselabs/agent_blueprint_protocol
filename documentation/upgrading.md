# Upgrading and stability

The 0.x series is the public pre-1.0 line: shipped contracts may
change within 0.x under pre-1.0 conventions, and every contract change
lands with a red-capable test. The CHANGELOG records every public
change; the release identity chain (specification digest, package
version, corpus and registry digests) is asserted from live state on
every build, so a release cannot ship with stale identity claims.

## Version axes

Hex semver, git release tags, the release-metadata fields, and the
digests themselves are the only version-bearing identities — no
identifier in the package carries a version token. Upgrading means a
new digest chain, not a renamed module.

## What never changes silently

Canonicalization (RFC 8785), the digest domain separators, the
closed member worlds per revision, and the non-authorizing boundary.
Evolution happens at digest-covered revision boundaries, gated by
negotiation.
