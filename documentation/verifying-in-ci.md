# Verify in CI

This guide is for maintainers and implementers. You will run the Elixir and npm conformance commands, save a results document, and check another implementation with the harness.

The corpus contains shared inputs and expected results. A passing run establishes agreement on those cases.

## Elixir

From the repository root, run the Mix alias to build and execute the Elixir conformance runner:

```sh
mix conformance.verify
```

To save the per-case results document, build the escript and run it with the results option:

```sh
mix escript.build
./agent_blueprint_protocol_conformance --results --corpus priv/conformance > results.json
```

The command writes the canonical results document to standard output and a corpus identity line to standard error.

## npm

Run the release-candidate CLI against the repository corpus:

```sh
npx @agent-blueprint-protocol/verifier@rc --results --corpus ./priv/conformance > results.json
```

The results document has the format name, corpus and registry digests, and one result row per case. It contains no implementation identity.

## Exit codes

| Command | Exit | Meaning |
|---|---:|---|
| Elixir corpus runner | 0 | All cases agree. |
| Elixir corpus runner | 1 | At least one case disagrees. |
| Elixir corpus runner | 2 | Usage, read, or corpus-integrity failure. |
| npm corpus runner | 0 | Agreement, a valid artifact, help, or version output. |
| npm corpus runner | 1 | Disagreement or invalid artifact. |
| npm corpus runner | 2 | Usage, read, or corpus-integrity failure. |
| npm corpus runner | 3 | Internal invariant failure. |
| External harness | 2 | Usage, corpus-integrity, or claim-input failure. |
| External harness | 10 | Handshake mismatch. |
| External harness | 11 | Duplicate response identifier. |
| External harness | 12 | A successful adapter exit omitted a response. |
| External harness | 13 | Extra response. |
| External harness | 14 | Response out of order or an unexpected identifier. |
| External harness | 15 | Malformed response line or response shape. |
| External harness | 16 | Response line exceeded its size limit. |
| External harness | 17 | Response missed its deadline. |
| External harness | 18 | Adapter could not start, exited early, or returned a nonzero status. |
| External harness | 19 | Result disagreed with the expected projection. |

The [runner contract](../spec/conformance/runner.md) defines result projections and runner statuses. The [execution protocol](../spec/conformance/execution.md) defines harness responses and exit codes.

## Check another implementation

Extract the corpus to ./conformance, then run the npm harness with the adapter executable after --. This command template is an excerpt. Replace `./example-adapter` with the adapter supplied by the implementation.

```sh
npx @agent-blueprint-protocol/verifier@rc conformance run --corpus ./conformance --results results.json -- ./example-adapter
```

The harness compares the adapter's complete result projections. It writes a results document after a clean run.

## Next steps

- [Conformance guide](conformance.md)
- [Architecture](architecture.md)
- [External execution protocol](../spec/conformance/execution.md)
