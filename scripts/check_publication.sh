#!/usr/bin/env bash
# A registry error is unknown state, never evidence that a version is free.
set -euo pipefail

EXPECTED_NPM=404
if [[ "${1:-}" == --after-npm && "$#" == 1 ]]; then
  EXPECTED_NPM=200
elif [[ "$#" != 0 ]]; then
  echo "::error::Expected no arguments or --after-npm"
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
  echo "::error::Refusing a package name the registry does not have or did not confirm"
  echo "A first publication is the owner's decision; this workflow never creates a package."
  exit 1
fi

NPM_STATUS=$(curl --silent --show-error --output /dev/null --write-out '%{http_code}' \
  --connect-timeout 10 --max-time 30 \
  "https://registry.npmjs.org/@agent-blueprint-protocol%2fverifier/${VERSION}")
HEX_STATUS=$(curl --silent --show-error --output /dev/null --write-out '%{http_code}' \
  --connect-timeout 10 --max-time 30 \
  "https://hex.pm/api/packages/agent_blueprint_protocol/releases/${VERSION}")
REMOTE_TAG=$(git ls-remote --tags origin "refs/tags/v${VERSION}")
TAG_STATE=absent
if [[ -n "$REMOTE_TAG" ]]; then TAG_STATE=present; fi
echo "Release ${VERSION}: npm HTTP ${NPM_STATUS}; Hex HTTP ${HEX_STATUS}; tag ${TAG_STATE}"

if [[ "$NPM_STATUS" != "$EXPECTED_NPM" || "$HEX_STATUS" != 404 || -n "$REMOTE_TAG" ]]; then
  echo "::error::Refusing occupied or unknown release state; nothing in this job was published"
  echo "A partial release or pending approval must be resolved by hand from verified artifacts."
  echo "Do not redispatch to resume or replace bytes. Read back each registry before tagging."
  exit 1
fi
