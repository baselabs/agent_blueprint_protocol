# The TypeScript quickstart — verify without Elixir

The verifier ships as an installable npm kit,
`@rjpalermo/agent-blueprint-protocol`: the compiled verifier, its
embedded conformance corpus (byte-identical to the release-certified
copy), and a single bin. Node 24 or newer; zero runtime dependencies.

## Verify the kit (one command)

```bash
npx @rjpalermo/agent-blueprint-protocol
```

With no arguments the kit runs its EMBEDDED corpus — 96 cases over
every protocol surface — and prints the single-line report. Green is
`"agreement":true` and exit 0; the report names the corpus digest, so
what you verified is an exact, identified byte set, not a vibe:

```json
{"agreed":94,"agreement":true,"corpus_digest":"sha-256:…","disagreed":0,"exit_status":0,"format":"agent-blueprint-protocol-conformance-report","total":94}
```

## Verify any corpus

The kit accepts `--corpus <dir>` (its only other mode): point it at
any conformance corpus directory — a copy extracted from a git release
tag's verification kit, or one you built yourself — and the same
integrity-first rules apply (missing files, hash mismatches, and empty
corpora are typed failures, exit 2; a tampered corpus cannot verify
green).

```bash
npx @rjpalermo/agent-blueprint-protocol --corpus ./conformance
```

## Verify one artifact file

`--artifact <file>` verifies a single JSON artifact — a Blueprint, a
Deployment Manifest, or a federation TaskEnvelope — against all three
kinds; valid iff any kind decodes. Green names the kind; a denial names
each kind's typed code, so the file's shape is legible from the report
alone:

```bash
$ npx @rjpalermo/agent-blueprint-protocol --artifact echo-blueprint.json
{"format":"agent-blueprint-protocol-artifact-report","kind":"blueprint","verdict":"valid"}
```

Exit 0 is a verified artifact (evidence, never authority); exit 1 is a
typed denial; exit 2 is a usage or readability failure. This mode is a
kit-side convenience — the Elixir escript deliberately keeps its
own CLI corpus-only — and its verdicts are gated: the release
agreement check replays every decode-surface corpus case through
`--artifact` and requires each case's own expected verdict.

## As a dependency

```bash
npm install @rjpalermo/agent-blueprint-protocol
```

The package exports the compiled verifier modules under
`dist/verifier/` with `.d.ts` declarations; the corpus loader, runner,
and every verification surface (decode, canonicalization, digests,
signatures, negotiation, bounds algebra, federation) are importable.
The Elixir reference implementation and this kit byte-agree on every
corpus verdict — that agreement is a release gate, not a claim.

## What verification means here

Exactly what it means in Elixir: a typed fact about bytes and
structure. Nothing is authorized, nothing executes, no key material is
held. See [what a blueprint is](what-a-blueprint-is.md), the [error
guide](errors.md), and — for how this kit's identity relates to
discovery-side trust manifests — the [ARD mapping](../docs/ard-mapping.md).
