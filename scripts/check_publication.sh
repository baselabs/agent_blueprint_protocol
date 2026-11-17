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
