# 0015: Three-platform support

Status: Accepted

## Context

Consumers and contributors clone and execute the same bytes on Linux, macOS and Windows.

## Decision

CI exercises byte-exact checkout, compilation, tests, corpus execution, kit build, external harness and packed consumption on all three platforms. Escript calls use the escript launcher. Platform-specific filesystem probes state their exclusions explicitly.

Filesystem globs keep the root in `:filelib.wildcard/2`'s working-directory argument and pass only the pattern as glob syntax. Windows backslashes are escapes, and brackets and braces in real directory names must remain literal. Scans that exclude dotfiles filter hidden relative path segments explicitly; corpus-loading examples include every regular file, including dotfiles. The architecture gate checks tracked source and documentation recipes for roots joined into patterns.

## Consequences

Maintainer publishing, secret scanning and filtered specification extraction remain Linux tooling. The byte-preserving attributes and clone-safety rules remain mandatory.
