#!/bin/bash

set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
FIXTURE=$(mktemp -d)
trap 'rm -rf -- "$FIXTURE"' EXIT

source "$ROOT/install/helpers/node-release.sh"

fail() {
  echo "not ok - $1" >&2
  exit 1
}

[[ $(omarchy-node-release-platform x86_64) == linux-x64 ]] || fail "maps x86_64 Node.js releases"
[[ $(omarchy-node-release-platform aarch64) == linux-arm64 ]] || fail "maps AArch64 Node.js releases"
if omarchy-node-release-platform riscv64 >/dev/null 2>&1; then
  fail "rejects unsupported Node.js architectures"
fi

touch "$FIXTURE/node-v24.7.0-linux-arm64.tar.gz"
node_archive=$(omarchy-find-node-release "$FIXTURE" linux-arm64)
[[ $node_archive == "$FIXTURE/node-v24.7.0-linux-arm64.tar.gz" ]] || fail "selects the AArch64 archive"
[[ $(omarchy-node-release-version "$node_archive" linux-arm64) == 24.7.0 ]] || fail "parses the AArch64 version"

touch "$FIXTURE/node-v24.7.1-linux-arm64.tar.gz"
if omarchy-find-node-release "$FIXTURE" linux-arm64 >/dev/null 2>&1; then
  fail "rejects duplicate AArch64 Node.js archives"
fi

echo "Node.js release handoff tests passed"
