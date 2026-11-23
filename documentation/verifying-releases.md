# Verify releases

This guide is for people checking installed or downloaded packages. You will compare the Hex checksum, npm signatures and integrity, release metadata, corpus digest, and GitHub release asset digest.

Use Node.js 24 or newer, npm, and Mix with Hex installed. These checks need no source checkout.

Every recipe defaults to `VERSION=1.1.1-rc.1`. To check another release, substitute its version consistently in every block and use the matching archives and installation. Expected checksums below are queried from the publishing service rather than copied from an older release.

## Verify a Hex package

Fetch the package archive, print the checksum from Hex's release API, then calculate the archive's SHA-256 value:

```sh
VERSION=1.1.1-rc.1
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
VERSION=1.1.1-rc.1
npm view "@agent-blueprint-protocol/verifier@$VERSION" dist.integrity
npm pack "@agent-blueprint-protocol/verifier@$VERSION" --json
```

Compare the registry's `dist.integrity` with the `integrity` field in the pack output. Run `npm audit signatures` after installing and locking this exact version.

## Compare release metadata and corpus identity

The package release metadata includes package_version and corpus_digest. The conformance index also includes corpus_digest. The values must match.

For the Hex package, extract the package archive, then compare priv/release-metadata.json with priv/conformance/index.json:

```sh
VERSION=1.1.1-rc.1
mkdir -p hex-wrapper hex-package
tar -xf "agent_blueprint_protocol-$VERSION.tar" -C hex-wrapper
tar -xzf hex-wrapper/contents.tar.gz -C hex-package
node --input-type=module -e 'import fs from "node:fs"; const [version, metadataPath, indexPath] = process.argv.slice(1); const m = JSON.parse(fs.readFileSync(metadataPath, "utf8")); const i = JSON.parse(fs.readFileSync(indexPath, "utf8")); if (m.package_version !== version || m.corpus_digest !== i.corpus_digest) process.exit(1); console.log(m.package_version + " " + m.corpus_digest);' "$VERSION" hex-package/priv/release-metadata.json hex-package/priv/conformance/index.json
```

For the npm package, compare dist/release-metadata.json with dist/corpus/index.json after installing the exact version:

```sh
VERSION=1.1.1-rc.1
node --input-type=module -e 'import fs from "node:fs"; const [version, metadataPath, indexPath] = process.argv.slice(1); const m = JSON.parse(fs.readFileSync(metadataPath, "utf8")); const i = JSON.parse(fs.readFileSync(indexPath, "utf8")); const p = JSON.parse(fs.readFileSync("node_modules/@agent-blueprint-protocol/verifier/package.json", "utf8")); if (p.version !== version || m.package_version !== version || m.corpus_digest !== i.corpus_digest) process.exit(1); console.log(m.package_version + " " + m.corpus_digest);' "$VERSION" node_modules/@agent-blueprint-protocol/verifier/dist/release-metadata.json node_modules/@agent-blueprint-protocol/verifier/dist/corpus/index.json
```

A mismatch in the installed package version or either corpus identity exits `1`.

## Verify the GitHub release asset

GitHub reports a SHA-256 digest for each release asset. This public-API recipe queries the expected digest, downloads the matching archive, compares the bytes, and saves the verified file. It requires no GitHub CLI session and refuses to overwrite an existing file:

```sh
VERSION=1.1.1-rc.1
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

## Verify SHA256SUMS and registry bytes

For releases carrying SHA256SUMS, download all assets from the GitHub release
`v<version>` into a fresh directory, using GitHub CLI or the release page:

```sh
VERSION=1.1.1-rc.1
gh release download "v$VERSION" --repo baselabs/agent_blueprint_protocol
sha256sum --check SHA256SUMS
```

Require every listed file to pass. Compare the release's
`agent_blueprint_protocol-<version>.tar` SHA-256 with the Hex release API checksum
using the Hex recipe above. Compare the release's npm tgz with the registry's
`dist.integrity` using the npm recipe. The `verifier-<version>.tar.gz` asset remains
the standalone verifier; its SHA-256 must also match SHA256SUMS and GitHub's asset
digest. A checksum file checks consistency; registry signatures and provenance
provide independent checks. Remove the downloaded files when finished.

## Consumer example verification

Once both registries and Hex docs are served, Publish
installs the published packages and runs their notebook, doctest,
Elixir snippet, and TypeScript example gates on Linux, macOS, and Windows,
then replays every earlier release census and the signed 0.8.x goldens
through the installed packages. CI builds both packages and runs the same
verification on those platforms before publication. From a checkout with
historical release tags available and Elixir and Node installed, run:

```sh
elixir scripts/verify_release_packages.exs --registry 1.1.1-rc.1
```

The script verifies the Hex archive against the Hex API release checksum and
the npm archive against `dist.integrity`, then extracts both in-process. It
loads the gates and example documents from the packages. `--local HEX.tar
NPM.tgz` accepts archives built by `mix hex.build` and
`npm pack ./dist/package --ignore-scripts` and runs the same verification.
Local mode verifies candidate bytes without requiring them to be published.
Both modes read the checkout's release tags to replay historical censuses and
the signed 0.8.x goldens under both installed packages. A missing tag history
fails verification; fetch the historical release tags before running either
mode. The version being verified does not need its own tag.

Without a checkout, the Hex package's own `scripts/consumer_examples.exs` takes
the same arguments and runs the four package gates alone. It loads nothing
outside the package.
See [Contributing](../CONTRIBUTING.md) for the build commands.

## Verify served docs provenance

Each release is built from one qualified commit. The published source commit is
recorded as `commit` in the docs archive's root `release.json` and identified by
the GitHub release's version tag. The manifest also names the package and version.

The GitHub release includes the served docs archive as
`hex-docs-<version>.tar.gz`, with its digest in SHA256SUMS. Verify that checksum
using the recipe above before inspecting `release.json`. In a source checkout,
fetch the release tag and compare its commit with the manifest:

```sh
VERSION=1.1.1-rc.1
git fetch origin tag "v$VERSION"
COMMIT=$(git rev-parse "v$VERSION^{commit}")
mkdir hex-docs
tar -xzf "hex-docs-$VERSION.tar.gz" -C hex-docs
node --input-type=module -e '
  import fs from "node:fs";
  const [version, commit] = process.argv.slice(1);
  const manifest = JSON.parse(fs.readFileSync("hex-docs/release.json", "utf8"));
  if (manifest.package !== "agent_blueprint_protocol" || manifest.version !== version ||
      !/^[0-9a-f]{40}$/.test(manifest.commit) || manifest.commit !== commit) {
    throw new Error("Docs provenance does not match the release tag");
  }
  if (!fs.existsSync("hex-docs/index.html")) throw new Error("Docs index missing");
  console.log("Verified docs provenance");
' "$VERSION" "$COMMIT"
```

The command exits nonzero if the package, version, source commit, or docs index
does not match. Remove the extracted `hex-docs` directory when finished.

Docs are a rendering whose bytes can vary between builds. Served docs are
preserved, so compare the inspected archive with the GitHub release asset rather
than with a rebuild. Equal package bytes alone do not identify the docs commit
because the renderer and build state also affect documentation. The manifest's
`commit` field records the qualified `release_commit` used to build those docs.
Preserved docs can identify an earlier source commit with the same package bytes.
The published version tag must identify that manifest commit.

## Next steps

- [Read the conformance guide](conformance.md)
- [Inspect the release metadata](https://github.com/baselabs/agent_blueprint_protocol/blob/v1.1.1-rc.1/priv/release-metadata.json)
- [Read the stability policy](stability.md)
