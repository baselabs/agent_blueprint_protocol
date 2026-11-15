# ADR: one continuous integration workflow

Status: accepted (2026-11-15).

## Context

Documentation in this repository is executable or gated: shipped guides run
from the package, citations must resolve, shipped text is checked for
currency and punctuation, and the specification must extract on its own. A
workflow that skips documentation-only changes, or a second workflow that
runs only after a change reaches the default branch, lets a change land
without the gates that cover it.

## Decision

One workflow gates every pull request and every push to the default branch
or a landing branch, with no path filter.
Every change, whether it touches code, documentation, the specification or
the workflows themselves, runs the same jobs before it lands. There is no
separate documentation workflow.

## Consequences

- The landing check for any change is that one workflow's run on the
  change's own commit.
- A documentation-only change costs a full run. That is the price of
  documentation that is executed and gated like code.
