# ADR: Conformance mutation checks

## Context

A passing corpus can be vacuous if it does not detect a broken verification rule. A command that already fails cannot establish that a mutation was caught.

## Decision

The conformance mutation gate first requires a green unmodified baseline for each distinct check command. Each mutation uses its own scratch replica and replaces exactly one matching source anchor. The mutated check must fail; a surviving mutation fails the gate. A calibration mutation exercises the corpus expectation check.

## Consequences

Missing or drifted anchors and failing baselines are gate failures, not caught mutations. Mutation checks demonstrate sensitivity to the named rules and do not establish behavior beyond those mutations.
