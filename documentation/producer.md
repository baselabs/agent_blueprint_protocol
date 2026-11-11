# Producer guide

This guide is for developers who publish Blueprints and Deployment Manifests. You will find the steps for composing, signing, and checking a producer artifact.

Compose each artifact from the protocol's tagged JSON values, then compute its digest and encode the canonical bytes. Keep producer data portable and use the exact member set for its protocol revision.

The [compose and sign guide](compose-and-sign.md) walks through a complete Blueprint built with `Blueprint.from_value/2`. It computes the digest, signs with the producer's own Ed25519 key using `:crypto`, attaches the signature, and checks the round trip.

## Next steps

- [What a Blueprint is](what-a-blueprint-is.md)
- [Compose and sign a Blueprint](compose-and-sign.md)
- [Read the security model](security-model.md)
