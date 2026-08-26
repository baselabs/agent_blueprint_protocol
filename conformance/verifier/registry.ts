// The compiled-in extension registry twin: the six entries (five
// first-release rows plus the estate-contract product registration) and
// the federation schema, with the registry content digest the corpus binds
// to. Agreement with the Elixir twin is proven by the corpus's own
// registry_digest check at load — neither side reads the other's source.

import * as digest from "./digest.ts";
import { encode } from "./canonical.ts";
import type { Value } from "./value.ts";
import { bool, int, nil, obj, str } from "./value.ts";

export type Criticality = "critical" | "optional";
export type RegState = "reserved" | "active" | "deprecated" | "retired";

export interface RegistryEntry {
  namespace: string;
  owner: string;
  criticality: Criticality;
  state: RegState;
  schema_digest: string | null; // tagged digest string, null until authored
  a2a_uri: string;
  promoted_at_revision: number | null;
}

// The federation envelope's minimal schema — owned by this package, inside
// the bounded dialect (closed object, no reserved-semantics names).
export function federationSchema(): Value {
  return obj([
    ["additionalProperties", bool(false)],
    [
      "properties",
      obj([
        ["issuer", obj([["type", str("string")]])],
        ["subject", obj([["type", str("string")]])],
        ["audience", obj([["type", str("string")]])],
      ]),
    ],
    ["type", str("object")],
  ]);
}

function taggedFederationDigest(): string {
  const jcs = encode(federationSchema());
  if (!jcs.ok) throw new Error("federation schema must encode");
  return digest.toTagged(digest.hash("extension_schema", Buffer.from(jcs.v, "utf8")));
}

function entries(): RegistryEntry[] {
  return [
    {
      namespace: "com.example.commerce/graph",
      owner: "ExampleCommerce",
      criticality: "critical",
      state: "active",
      schema_digest: null,
      a2a_uri: "https://example.com/extensions/commerce-graph",
      promoted_at_revision: null,
    },
    {
      namespace: "com.example.commerce/classification-labels",
      owner: "ExampleCommerce",
      criticality: "optional",
      state: "active",
      schema_digest: null,
      a2a_uri: "https://example.com/extensions/commerce-classification-labels",
      promoted_at_revision: null,
    },
    {
      namespace: "com.example.commerce/rubric-assertion",
      owner: "ExampleCommerce",
      criticality: "optional",
      state: "active",
      schema_digest: null,
      a2a_uri: "https://example.com/extensions/commerce-rubric-assertion",
      promoted_at_revision: null,
    },
    {
      namespace: "com.example.platform/estate",
      owner: "ExamplePlatform",
      criticality: "optional",
      state: "deprecated",
      schema_digest: null,
      a2a_uri: "https://example.com/extensions/platform-estate",
      promoted_at_revision: null,
    },
    {
      // The product-extension registration: the first product-owned critical
      // pin. The document is corpus data (schemas/estate-contract.schema.json);
      // this digest is JCS-of-parsed-document under the extension-schema
      // domain, bound to the shipped file by the Elixir pin test.
      namespace: "com.example.platform/estate-contract",
      owner: "ExamplePlatform",
      criticality: "critical",
      state: "active",
      schema_digest: "sha-256:s_ToZWwxrhhd4vVxAyUh2Q6Gddston4tBSLHTLvCQAw",
      a2a_uri: "https://example.com/extensions/platform-estate-contract",
      promoted_at_revision: null,
    },
    {
      namespace: "com.example/federation",
      owner: "Agent Blueprint Protocol",
      criticality: "critical",
      state: "active",
      schema_digest: taggedFederationDigest(),
      a2a_uri: "https://example.com/extensions/federation",
      promoted_at_revision: null,
    },
  ];
}

export function registeredExtensions(): RegistryEntry[] {
  return entries();
}

export function entry(namespace: string): RegistryEntry | null {
  return entries().find((candidate) => candidate.namespace === namespace) ?? null;
}

// The registry content digest (the corpus-registry binding): hash over the
// JCS of entries projected to their declared field set, keyed by namespace.
export function registryDigest(): string {
  const projected = obj(
    entries().map((entry) => [
      entry.namespace,
      obj([
        ["a2a_uri", str(entry.a2a_uri)],
        ["criticality", str(entry.criticality)],
        ["owner", str(entry.owner)],
        [
          "promoted_at_revision",
          entry.promoted_at_revision === null ? nil : int(entry.promoted_at_revision),
        ],
        ["schema_digest", entry.schema_digest === null ? nil : str(entry.schema_digest)],
        ["state", str(entry.state)],
      ]),
    ]),
  );
  const jcs = encode(projected);
  if (!jcs.ok) throw new Error("registry projection must encode");
  return digest.toTagged(digest.hash("extension_registry", Buffer.from(jcs.v, "utf8")));
}
