# Verify releases

This guide is for people checking installed or downloaded packages. You will compare the Hex checksum, npm signatures and integrity, release metadata, corpus digest, and GitHub release asset digest.

Use Node.js 24 or newer, npm, and Mix with Hex installed. These checks need no source checkout.

Every recipe defaults to `VERSION=1.0.1`. To check another release, substitute its version consistently in every block and use the matching archives and installation. Expected checksums below are queried from the publishing service rather than copied from an older release.

## Verify a Hex package

Fetch the package archive, print the checksum from Hex's release API, then calculate the archive's SHA-256 value:

```sh
VERSION=1.0.1
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

Compare the two printed SHA-256 values; they must match.

## Verify npm signatures and tarball integrity

Run npm audit signatures in a project that has the package installed and locked. It checks registry signatures and provenance attestations for the locked packages.

```sh
npm audit signatures
```

Check the published tarball integrity in the registry and in the packed archive:

```sh
VERSION=1.0.1
npm view "@agent-blueprint-protocol/verifier@$VERSION" dist.integrity
npm pack "@agent-blueprint-protocol/verifier@$VERSION" --json
```

Compare the registry's `dist.integrity` with the `integrity` field in the pack output. Run `npm audit signatures` after installing and locking this exact version.

## Compare release metadata and corpus identity

The package release metadata includes package_version and corpus_digest. The conformance index also includes corpus_digest. The values must match.

For the Hex package, extract the package archive, then compare priv/release-metadata.json with priv/conformance/index.json:

```sh
VERSION=1.0.1
mkdir -p hex-wrapper hex-package
tar -xf "agent_blueprint_protocol-$VERSION.tar" -C hex-wrapper
tar -xzf hex-wrapper/contents.tar.gz -C hex-package
node --input-type=module -e 'import fs from "node:fs"; const [version, metadataPath, indexPath] = process.argv.slice(1); const m = JSON.parse(fs.readFileSync(metadataPath, "utf8")); const i = JSON.parse(fs.readFileSync(indexPath, "utf8")); if (m.package_version !== version || m.corpus_digest !== i.corpus_digest) process.exit(1); console.log(m.package_version + " " + m.corpus_digest);' "$VERSION" hex-package/priv/release-metadata.json hex-package/priv/conformance/index.json
```

For the npm package, compare dist/release-metadata.json with dist/corpus/index.json after installing the exact version:

```sh
VERSION=1.0.1
node --input-type=module -e 'import fs from "node:fs"; const [version, metadataPath, indexPath] = process.argv.slice(1); const m = JSON.parse(fs.readFileSync(metadataPath, "utf8")); const i = JSON.parse(fs.readFileSync(indexPath, "utf8")); const p = JSON.parse(fs.readFileSync("node_modules/@agent-blueprint-protocol/verifier/package.json", "utf8")); if (p.version !== version || m.package_version !== version || m.corpus_digest !== i.corpus_digest) process.exit(1); console.log(m.package_version + " " + m.corpus_digest);' "$VERSION" node_modules/@agent-blueprint-protocol/verifier/dist/release-metadata.json node_modules/@agent-blueprint-protocol/verifier/dist/corpus/index.json
```

A mismatch in the installed package version or either corpus identity exits `1`.

## Verify the GitHub release asset

GitHub reports a SHA-256 digest for each release asset. This public-API recipe queries the expected digest, downloads the matching archive, compares the bytes, and saves the verified file. It requires no GitHub CLI session and refuses to overwrite an existing file:

```sh
VERSION=1.0.1
node --input-type=module -e '
  import { createHash } from "node:crypto";
  import { writeFileSync } from "node:fs";
  const version = process.argv[1];
  const response = await fetch(`https://api.github.com/repos/baselabs/agent_blueprint_protocol/releases/tags/v${version}`);
  if (!response.ok) throw new Error(`GitHub returned ${response.status}`);
  const release = await response.json();
  const filename = `verifier-${version}.tar.gz`;
  const asset = release.assets.find(item => item.name === filename);
  if (!asset || typeof asset.digest !== "string") throw new Error("Release asset or digest missing");
  const download = await fetch(asset.browser_download_url);
  if (!download.ok) throw new Error(`Download returned ${download.status}`);
  const bytes = new Uint8Array(await download.arrayBuffer());
  const actual = "sha256:" + createHash("sha256").update(bytes).digest("hex");
  if (actual !== asset.digest) throw new Error("Release asset digest mismatch");
  writeFileSync(filename, bytes, {flag: "wx"});
  console.log(actual);
' "$VERSION"
```

The command prints the matching digest and exits `0`; a missing asset, failed download, or mismatch exits nonzero. The archive contains `release-metadata.json` and `conformance/index.json` for the same corpus comparison. Run these recipes in a fresh working directory; keep verified archives deliberately or remove the downloaded archives and extracted example directories when finished.

## Next steps

- [Read the conformance guide](conformance.md)
- [Inspect the release metadata](https://github.com/baselabs/agent_blueprint_protocol/blob/v1.0.1/priv/release-metadata.json)
- [Read the stability policy](stability.md)
