# Producer guide

This guide is for developers who publish Blueprints and Deployment Manifests. You will find the steps for composing, signing, and checking a producer artifact.

Compose each artifact from the protocol's tagged JSON values, then compute its digest and encode the canonical bytes. Keep producer data portable and use the exact member set for its protocol revision.

The [compose and sign guide](compose-and-sign.md) walks through a complete signed pair built with `Blueprint.from_value/2`. It computes both digests, signs with the producer's own Ed25519 key using `:crypto`, attaches the signature, checks the pair and round trips, and saves files for CI.

## Next steps

- [What a Blueprint is](what-a-blueprint-is.md)
- [Compose and sign artifacts](compose-and-sign.md)
- [Read the security model](security-model.md)
