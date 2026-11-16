# ADR: producer surface policy

## Decision

The constructors ARE the intended producer surface. The facade stays a
verification facade: it delegates and never implements, and no facade-level
producer functions grow. Compose the tagged JSON value with a well-formed provisional digest. Construct a draft with the artifact's `from_value/2`, compute `content_digest/1`, convert it with `Digest.to_tagged/1`, and replace the value's `content_digest` or `deployment_digest` member. Canonically encode the updated value and decode those bytes to validate the completed artifact. Sign the completed digest and recreate any signatures affected by the edit. Supply `:authored_extensions` from negotiation of that same value for critical namespaces whose bodies were validated against a digest-pinned schema. The round-trip
property (`decode → to_value → encode` is a fixed point) is the byte-exactness
guarantee a producer relies on.

## Member introspection

`Blueprint.members/1`, `Deployment.members/1` and `Federation.members/1`
return the sorted core member names of a protocol revision, read from the
same tables the decoders use, so a host can build negotiation support
without copying the member lists. Revision 1 is supported; another integer
returns `protocol_revision_unsupported` and a non-integer returns
`invalid_type`. The TypeScript verifier exports the same lists as
`blueprintMembers`, `deploymentMembers` and `federationMembers`.

Introspection is read only. It adds no facade constructor, and it does not
make a revision's member set extensible: the closed world of each revision
is unchanged.
