#!/usr/bin/env bash
# A registry error is unknown state, never evidence that a version is free.
set -euo pipefail

if [[ "$#" != 0 ]]; then
  echo "::error::Expected no arguments"
  exit 1
fi
: "${VERSION:?The release input reader must provide VERSION}"

# A name the registry does not have would be created by publishing it. A first
# publication is the owner's decision, so both package names must already exist.
NPM_PACKAGE_STATUS=$(curl --silent --show-error --output /dev/null --write-out '%{http_code}' \
  --connect-timeout 10 --max-time 30 --header 'Accept: application/vnd.npm.install-v1+json' \
  "https://registry.npmjs.org/@agent-blueprint-protocol%2fverifier")
HEX_PACKAGE_STATUS=$(curl --silent --show-error --output /dev/null --write-out '%{http_code}' \
  --connect-timeout 10 --max-time 30 \
  "https://hex.pm/api/packages/agent_blueprint_protocol")
echo "Packages: npm HTTP ${NPM_PACKAGE_STATUS}; Hex HTTP ${HEX_PACKAGE_STATUS}"

if [[ "$NPM_PACKAGE_STATUS" != 200 || "$HEX_PACKAGE_STATUS" != 200 ]]; then
  echo "::error::Refusing @agent-blueprint-protocol/verifier or agent_blueprint_protocol: package missing or registry state unknown"
  echo "A first publication is the owner's decision; this workflow never creates a package."
  exit 1
fi

REMOTE_TAG=$(git ls-remote --tags origin "refs/tags/v${VERSION}")
TAG_STATE=absent
if [[ -n "$REMOTE_TAG" ]]; then TAG_STATE=present; fi
echo "Release ${VERSION}: tag ${TAG_STATE}"
if [[ -n "$REMOTE_TAG" ]]; then
  echo "::error::Refusing an existing release tag; use a new version"
  exit 1
fi
