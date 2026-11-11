# Verify releases

This guide is for people checking installed or downloaded packages. You will compare the Hex checksum, npm signatures and integrity, release metadata, corpus digest, and GitHub release asset digest.

Set VERSION to the package version you installed, for example 1.0.0. The worked values below are for the published 0.8.4 release.

## Verify a Hex package

Fetch the package archive, print the checksum from Hex's release API, then calculate the archive's SHA-256 value:

```sh
VERSION=0.8.4
mix hex.package fetch agent_blueprint_protocol "$VERSION"
node --input-type=module -e '
  const version = process.argv[1];
  const response = await fetch(`https://hex.pm/api/packages/agent_blueprint_protocol/releases/${version}`);
  if (!response.ok) throw new Error(`Hex returned ${response.status}`);
  const release = await response.json();
  console.log(release.checksum);
' "$VERSION"
node -e 'const fs = require("node:fs"); const crypto = require("node:crypto"); console.log(crypto.createHash("sha256").update(fs.readFileSync(process.argv[1])).digest("hex"));' "agent_blueprint_protocol-$VERSION.tar"
```

For published version 0.8.4, Hex reports checksum 2d6b7c972e6d6df04f099017c7d09e517de4cd3e1bc06d627a86d76fd27a35b2. The command prints the archive checksum. The values must match.

For this release, replace the first line with VERSION=1.0.0 and compare the fetched archive value with the checksum reported by Hex.

## Verify npm signatures and tarball integrity

Run npm audit signatures in a project that has the package installed and locked. It checks registry signatures and provenance attestations for the locked packages.

```sh
npm audit signatures
```

Check the published tarball integrity in the registry and in the packed archive:

```sh
VERSION=0.8.4
npm view "@agent-blueprint-protocol/verifier@$VERSION" dist.integrity
npm pack "@agent-blueprint-protocol/verifier@$VERSION" --json
```

For 0.8.4, both values are sha512-TiYvqPJbjiv7iiUDHDjbkuA/nifUHMaqBETNdRTxFddCw5sQmrzq7yi1ruaxJK63loND+3enA47ULCv3K1Wn2Q==. Compare the registry's dist.integrity value with the integrity field in the pack output.

For this release, use VERSION=1.0.0. Run npm audit signatures after installing that exact version in the project you are checking.

## Compare release metadata and corpus identity

The package release metadata includes package_version and corpus_digest. The conformance index also includes corpus_digest. The values must match.

For the Hex package, extract the package archive, then compare priv/release-metadata.json with priv/conformance/index.json:

```sh
VERSION=0.8.4
mkdir -p hex-wrapper hex-package
tar -xf "agent_blueprint_protocol-$VERSION.tar" -C hex-wrapper
tar -xzf hex-wrapper/contents.tar.gz -C hex-package
node --input-type=module -e 'import fs from "node:fs"; const [version, metadataPath, indexPath] = process.argv.slice(1); const m = JSON.parse(fs.readFileSync(metadataPath, "utf8")); const i = JSON.parse(fs.readFileSync(indexPath, "utf8")); if (m.package_version !== version || m.corpus_digest !== i.corpus_digest) process.exit(1); console.log(m.package_version + " " + m.corpus_digest);' "$VERSION" hex-package/priv/release-metadata.json hex-package/priv/conformance/index.json
```

For the npm package, compare dist/release-metadata.json with dist/corpus/index.json after installing the exact version:

```sh
VERSION=0.8.4
node --input-type=module -e 'import fs from "node:fs"; const [version, metadataPath, indexPath] = process.argv.slice(1); const m = JSON.parse(fs.readFileSync(metadataPath, "utf8")); const i = JSON.parse(fs.readFileSync(indexPath, "utf8")); const p = JSON.parse(fs.readFileSync("node_modules/@agent-blueprint-protocol/verifier/package.json", "utf8")); if (p.version !== version || m.package_version !== version || m.corpus_digest !== i.corpus_digest) process.exit(1); console.log(m.package_version + " " + m.corpus_digest);' "$VERSION" node_modules/@agent-blueprint-protocol/verifier/dist/release-metadata.json node_modules/@agent-blueprint-protocol/verifier/dist/corpus/index.json
```

For another release, replace `VERSION=0.8.4` with its package version. Use the matching Hex archive and npm installation.

The 0.8.4 corpus digest is sha-256:305LYavPWYaZP_pYGcZBPploy27btWTyMhiKd7XiRb8. The release metadata and conformance index must both report it.

## Verify the GitHub release asset

GitHub reports a SHA-256 digest for each release asset. Download the verifier archive and calculate its SHA-256 value:

```sh
VERSION=0.8.4
gh release view "v$VERSION" --repo baselabs/agent_blueprint_protocol --json assets
gh release download "v$VERSION" --repo baselabs/agent_blueprint_protocol --pattern "verifier-$VERSION.tar.gz"
node -e 'const fs = require("node:fs"); const crypto = require("node:crypto"); console.log("sha256:" + crypto.createHash("sha256").update(fs.readFileSync(process.argv[1])).digest("hex"));' "verifier-$VERSION.tar.gz"
```

The 0.8.4 release asset digest is sha256:d0e161be34bdfebaab2c9b991b40fac3867110f28504763a95f9cfc8a4d86fd6. Compare it with the value reported by the command.

For this release, set VERSION to 1.0.0. The asset contains release-metadata.json and conformance/index.json for the same corpus comparison.

## Next steps

- [Read the conformance guide](conformance.md)
- [Inspect the release metadata](https://github.com/baselabs/agent_blueprint_protocol/blob/v1.0.0/priv/release-metadata.json)
- [Read the stability policy](stability.md)
