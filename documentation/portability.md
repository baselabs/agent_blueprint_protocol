# Portability — the data-minimization profile

Portable artifacts MUST NOT carry secrets, private keys, live grants,
tenant identifiers, raw endpoints, database primary keys, or backend
engine identifiers. The guard is structural — member-name and
value-shape denylists over the open regions, at any depth,
name-spelling-normalized — and every class is red-cased in the corpus.

## The honest limits (part of the contract)

- The guard is necessary, not sufficient. Opaque quarantined extension
  bodies are typed as unscanned; portability claims attach only to
  schema-validated content.
- Identifier-shaped values with the UUID grammar are exempt by shape:
  the guard is structural, not semantic — a tenant identifier encoded
  as a UUID is not caught by the value-shape arm.

## What the host owns

Concrete provider/model names, credentials, engine ids, and endpoints
resolve host-side. A blueprint names logical operations and datasets;
a deployment binds them through identities and digests — never through
live coordinates.
