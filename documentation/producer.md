# Producer guide

This guide is for developers who publish Blueprints and Deployment Manifests. You will find the steps for composing, signing, and checking a producer artifact.

Compose the tagged JSON value with a well-formed provisional digest. Construct a draft with the artifact's `from_value/2`, compute `content_digest/1`, convert it with `Digest.to_tagged/1`, and replace the value's `content_digest` or `deployment_digest` member. Canonically encode the updated value and decode those bytes to validate the completed artifact. Sign the completed digest and recreate any signatures affected by the edit. Keep producer data portable and use the exact member set for its protocol revision.

The [compose and sign guide](compose-and-sign.md) walks through a complete signed pair built with `Blueprint.from_value/2`. It computes and inserts both digests, signs with the producer's own Ed25519 key using `:crypto`, attaches the signature, checks the pair and round trips, and saves files for CI.

## Next steps

- [What a Blueprint is](what-a-blueprint-is.md)
- [Compose and sign artifacts](compose-and-sign.md)
- [Read the security model](security-model.md)
