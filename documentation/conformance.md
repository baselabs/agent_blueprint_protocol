# Conformance guide

This guide is for implementers of another Agent Blueprint Protocol verifier. You will obtain the [conformance corpus](glossary.md#conformance-corpus), interpret its cases, write an execution adapter, and publish a reproducible conformance claim.

## Get the corpus

The [Hex package](https://hex.pm/packages/agent_blueprint_protocol) includes the corpus under `priv/conformance/`. In an installed Elixir project, find it at `Application.app_dir(:agent_blueprint_protocol, "priv/conformance")`.

The npm kit includes the same files under `node_modules/@agent-blueprint-protocol/verifier/dist/corpus/`. The [release asset](https://github.com/baselabs/agent_blueprint_protocol/releases/download/v1.0.0-rc.1/verifier-1.0.0-rc.1.tar.gz) stores them under `conformance/`.

## Case format and schemas

The [runner contract](https://github.com/baselabs/agent_blueprint_protocol/blob/v1.0.0-rc.1/spec/conformance/runner.md) defines corpus integrity, input dispatch, expected projections, and results. The [execution protocol](https://github.com/baselabs/agent_blueprint_protocol/blob/v1.0.0-rc.1/spec/conformance/execution.md) defines the process exchange.

The corpus index is `index.json`. Its schema is [`index.schema.json`](https://github.com/baselabs/agent_blueprint_protocol/blob/v1.0.0-rc.1/spec/conformance/index.schema.json). It lists the case files and data files, their hashes, the case totals, and the corpus and registry identities.

Each `cases/*.json` file uses [`case-file.schema.json`](https://github.com/baselabs/agent_blueprint_protocol/blob/v1.0.0-rc.1/spec/conformance/case-file.schema.json). A case contains an `id`, `surface`, `class`, `input`, and `expected` value. Each case also validates against its surface schema:

- `base64url.decode`: [`base64url-decode.schema.json`](https://github.com/baselabs/agent_blueprint_protocol/blob/v1.0.0-rc.1/spec/conformance/base64url-decode.schema.json)
- `blueprint.decode`: [`blueprint-decode.schema.json`](https://github.com/baselabs/agent_blueprint_protocol/blob/v1.0.0-rc.1/spec/conformance/blueprint-decode.schema.json)
- `bounds.new`: [`bounds-new.schema.json`](https://github.com/baselabs/agent_blueprint_protocol/blob/v1.0.0-rc.1/spec/conformance/bounds-new.schema.json)
- `bounds_algebra.intersect`: [`bounds_algebra-intersect.schema.json`](https://github.com/baselabs/agent_blueprint_protocol/blob/v1.0.0-rc.1/spec/conformance/bounds_algebra-intersect.schema.json)
- `canonicalization.encode`: [`canonicalization-encode.schema.json`](https://github.com/baselabs/agent_blueprint_protocol/blob/v1.0.0-rc.1/spec/conformance/canonicalization-encode.schema.json)
- `compatibility.verify`: [`compatibility-verify.schema.json`](https://github.com/baselabs/agent_blueprint_protocol/blob/v1.0.0-rc.1/spec/conformance/compatibility-verify.schema.json)
- `deployment.decode`: [`deployment-decode.schema.json`](https://github.com/baselabs/agent_blueprint_protocol/blob/v1.0.0-rc.1/spec/conformance/deployment-decode.schema.json)
- `digest.tagged`: [`digest-tagged.schema.json`](https://github.com/baselabs/agent_blueprint_protocol/blob/v1.0.0-rc.1/spec/conformance/digest-tagged.schema.json)
- `extension.resolve`: [`extension-resolve.schema.json`](https://github.com/baselabs/agent_blueprint_protocol/blob/v1.0.0-rc.1/spec/conformance/extension-resolve.schema.json)
- `federation.decode`: [`federation-decode.schema.json`](https://github.com/baselabs/agent_blueprint_protocol/blob/v1.0.0-rc.1/spec/conformance/federation-decode.schema.json)
- `federation.verify_commitment`: [`federation-verify_commitment.schema.json`](https://github.com/baselabs/agent_blueprint_protocol/blob/v1.0.0-rc.1/spec/conformance/federation-verify_commitment.schema.json)
- `json.decode`: [`json-decode.schema.json`](https://github.com/baselabs/agent_blueprint_protocol/blob/v1.0.0-rc.1/spec/conformance/json-decode.schema.json)
- `negotiation.negotiate`: [`negotiation-negotiate.schema.json`](https://github.com/baselabs/agent_blueprint_protocol/blob/v1.0.0-rc.1/spec/conformance/negotiation-negotiate.schema.json)
- `portability.scan`: [`portability-scan.schema.json`](https://github.com/baselabs/agent_blueprint_protocol/blob/v1.0.0-rc.1/spec/conformance/portability-scan.schema.json)
- `predicate`: [`predicate.schema.json`](https://github.com/baselabs/agent_blueprint_protocol/blob/v1.0.0-rc.1/spec/conformance/predicate.schema.json)
- `reconcile`: [`reconcile.schema.json`](https://github.com/baselabs/agent_blueprint_protocol/blob/v1.0.0-rc.1/spec/conformance/reconcile.schema.json)
- `schema.validate_instance`: [`schema-validate_instance.schema.json`](https://github.com/baselabs/agent_blueprint_protocol/blob/v1.0.0-rc.1/spec/conformance/schema-validate_instance.schema.json)
- `signature.verify`: [`signature-verify.schema.json`](https://github.com/baselabs/agent_blueprint_protocol/blob/v1.0.0-rc.1/spec/conformance/signature-verify.schema.json)

The successful reconcile projection also uses [`evidence.schema.json`](https://github.com/baselabs/agent_blueprint_protocol/blob/v1.0.0-rc.1/spec/conformance/evidence.schema.json); its support object uses [`support.schema.json`](https://github.com/baselabs/agent_blueprint_protocol/blob/v1.0.0-rc.1/spec/conformance/support.schema.json). The normative directory contains [the complete conformance schemas](https://github.com/baselabs/agent_blueprint_protocol/tree/v1.0.0-rc.1/spec/conformance).

## Write an execution adapter

An [execution adapter](glossary.md#execution-adapter) reads one JSON object per line from standard input and writes one JSON response per line. It first answers the handshake with the same protocol, version, corpus digest, and registry digest. It then handles requests in order. A response contains the request `id` and the complete result projection for that case.

The following transcript was captured while the kit harness ran the kit's own `--serve` adapter over its shipped corpus. The handshake request was:

```json
{"corpus_digest":"sha-256:oYnkSmTkHGk4AmZ8Sul99_6KYJUIuj2SN2GZAiT1glw","protocol":"agent-blueprint-protocol-conformance-execution","registry_digest":"sha-256:d98vF3duE_8P7N5aGLrmaqcj3uSDf0NsI4dzF7bXBDg","version":1}
```

The adapter answered:

```json
{"corpus_digest":"sha-256:oYnkSmTkHGk4AmZ8Sul99_6KYJUIuj2SN2GZAiT1glw","protocol":"agent-blueprint-protocol-conformance-execution","registry_digest":"sha-256:d98vF3duE_8P7N5aGLrmaqcj3uSDf0NsI4dzF7bXBDg","version":1}
```

The first case request was:

```json
{"id":"base64url-decode-exact-bound","input":{"base64url":"QQQ"},"surface":"base64url.decode"}
```

The adapter response was:

```json
{"id":"base64url-decode-exact-bound","result":{"decoded":"QQQ","verdict":"valid"}}
```

The command below runs the harness against the kit's own adapter. Run it from a directory that contains the extracted corpus at `./conformance`:

```sh
npx @agent-blueprint-protocol/verifier@rc conformance run --corpus ./conformance --results results.json -- npx @agent-blueprint-protocol/verifier@rc --serve --corpus ./conformance
```

## Read and compare results

A [results document](glossary.md#results-document) contains `format`, `corpus_digest`, `registry_digest`, and one `id`, `surface`, and `result` object per case. The harness writes it to the path given by `--results`. The release-certified document is [`certified-results.json`](https://github.com/baselabs/agent_blueprint_protocol/blob/v1.0.0-rc.1/spec/conformance/certified-results.json). For the release corpus, the harness compares each complete projection with that document. A successful run exits `0` and writes `harness: agreement` to standard error.

## Publish a claim

After a successful run, provide `--claim`, `--implementation`, `--implementation-version`, `--source`, `--platform`, and `--date` to the harness. The [claim schema](https://github.com/baselabs/agent_blueprint_protocol/blob/v1.0.0-rc.1/spec/conformance/claim.schema.json) defines the claim document. Publish the claim with the results document, source revision, and command used to run the adapter.

## What a pass establishes

The expected answers are public, so a pass does not establish how an implementation produced its output. The corpus covers only its listed cases. A pass says nothing about [host](glossary.md#host) behavior.

## Next steps

- [Quickstart](quickstart.md)
- [TypeScript guide](typescript.md)
- [Protocol specification](../spec/protocol.md)
- [Conformance schemas](https://github.com/baselabs/agent_blueprint_protocol/tree/v1.0.0-rc.1/spec/conformance)
