# ADR: Conformance product

Status: accepted (2026-11-10).

## Context

An aggregate count cannot establish case-by-case agreement for an external implementation.

## Decision

The normative corpus format, runner contract, canonical results document, unsigned claim, and process execution protocol ship with both distributions. One harness drives both adapters and compares projected verdicts independently. It rejects transport faults separately from protocol errors. A pass proves agreement only for the identified public census; it proves neither honest computation nor host behavior.

## Consequences

Format schemas live under spec/conformance so prior corpus file sets remain replayable. Certified results are a standalone artifact. Corpus changes remain additive within a semantics version.
