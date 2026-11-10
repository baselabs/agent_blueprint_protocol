# External conformance execution

This document is normative for conformance adapters. It specifies a process
transport, not a host execution or authorization protocol.

The harness spawns the command after `--`. Stdin and stdout carry UTF-8 JSON,
one object per LF-terminated line. Stdout has no banners. Stderr is diagnostic.
Each line, including LF, is at most 5,000,000 bytes. The harness defaults to
30,000 ms for each response, configurable from 1 to 300,000 ms.

The first harness line has exactly `protocol` equal to
`agent-blueprint-protocol-conformance-execution`, integer `version` equal to
1, `corpus_digest`, and `registry_digest`. The adapter MUST answer with the
same four members populated from its own corpus/registry view. Either side
MUST refuse a mismatch before executing cases.

Subsequent requests have exactly `{id, surface, input}`. They never carry
`expected`. Inputs and their referenced corpus data have the meaning in the
[runner contract](runner.md). An adapter resolves sidecars and schema files
from the corpus it identified at handshake. Requests arrive sorted by case
id. The adapter MUST emit exactly one `{id, result}` line in request order.
`result` is the complete projection specified by the runner contract, never
a boolean comparison with an answer supplied by the harness. Requests can
be pipelined. EOF on stdin ends the run; the adapter MUST drain its responses
and exit successfully. It MUST NOT emit an extra completion line.

For the release-certified corpus the harness checks each complete projection
against the shipped certified document, including the absence of extra result
members. For a named prior census it checks that census's expected fields.
It writes the canonical results
document, and exits nonzero on disagreement. Transport outcomes are harness
outcomes, not additions to the protocol's closed error vocabulary:

| Exit | Outcome |
|---|---|
| 0 | agreement |
| 2 | usage, corpus integrity, or claim-input failure |
| 10 | handshake_mismatch |
| 11 | duplicate_id |
| 12 | missing_response: successful adapter exit after some but not all replies |
| 13 | extra_response |
| 14 | reordered_response (including an unexpected id) |
| 15 | malformed_line (including wrong response members or unterminated line) |
| 16 | oversized_line |
| 17 | response_timeout: a response missed its deadline; a later response cannot restore success |
| 18 | early_exit: spawn failure, nonzero exit, or exit before the first case response |
| 19 | disagreement |

A successful exit with all expected responses is required even when every
individual projected verdict agrees. An adapter that exits before returning
its final responses cannot pass. Failure precedence follows observation:
line framing and shape, duplicate detection, order, agreement, then clean
termination. Clean process termination has the same deadline as a response,
even if stdout has already closed. A deadline failure ends the process and invalidates late output.

## Running and publishing a claim

The npm kit supplies the harness:

```sh
agent-blueprint-protocol conformance run --corpus ./conformance --results results.json -- ./example-adapter
```

After a pass, `--claim claim.json --implementation example-verifier
--implementation-version 1 --source https://example.com/source
--platform example-platform --date 2026-11-10` emits an unsigned claim.
`claim.schema.json` defines its format. The fields identify implementation,
version, source URL, platform, corpus digest, registry digest, SHA-256 digest
of the exact results document (`sha-256:` plus unpadded base64url), and date.

A claim requires the release-certified corpus. To claim a named prior census,
use `--prior-corpus-digest <exact-tagged-digest>` explicitly; that value MUST
match the loaded prior corpus and appear in the shipped release history. A non-certified corpus never silently becomes
a current-release claim. Publish the claim beside the exact results document,
source revision and reproducible command on the implementation's own release
page. No claim registry is created by this specification.

A corpus pass does not prove honest computation: the corpus and its expected
answers are public. It proves nothing outside that corpus census. It says
nothing about any host behavior, trust selection, authorization, or execution.
