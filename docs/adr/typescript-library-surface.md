# ADR: TypeScript library surface

Status: accepted (2026-11-10).

## Context

Internal deep imports exposed implementation layout and required consumers to know internal result records.

## Decision

The package root exports the verification facade, typed options, exhaustive errors and conformance operations. Only the root and package metadata resolve. Public declarations use strings and Uint8Array, and import runs no command or filesystem operation. Reconcile follows the existing eight-stage reference behavior.

## Consequences

The packed consumer checks actual installation, declarations without Node global types, deep-import rejection, exhaustive errors and every facade operation. The assembly root carries the package README without rewriting the repository README.
