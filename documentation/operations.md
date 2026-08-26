# Operations — running the battery and reading reports

## The full battery

```bash
mix quality
```

Dependency audits, format, warnings-as-errors compile, strict Credo,
tests at 100% coverage, the corpus and its mutation gate, the
second-language agreement gate (Node >= 24), Dialyzer, docs, the
specification-extraction check, the grammar-derivation gate, the
registry-equality gate, the release-asset gate, and the
release-candidate check (requirement-map completeness, specification
coupling, identity chain, and the reprove that replants every
recorded red).

## Reading a corpus report

One line, JCS-canonical: `{"agreed":N,"agreement":true,…}`. Exit 0
agreement, 1 disagreement (report still prints), 2 usage/integrity.
The report refuses a vacuous green.

## When a gate reds

Every gate's recorded red proof lives in the requirement map — the
exact mutation, command, and verbatim output. Find the gate, read its
fence, reproduce it. A red you cannot reproduce is a bug in the gate.
