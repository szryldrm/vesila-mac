#!/bin/bash
set -euo pipefail

# Runs Vesila's unit tests. Extra arguments are passed to `swift test` (e.g. --filter Presence).
#
# With only the Command Line Tools installed, the Swift Build backend doesn't hand the Swift
# Testing macro plugin to the compiler, and plain `swift test` fails with "plugin for module
# 'TestingMacros' not found". Passing the active toolchain's plugin directory works around it,
# and is harmless where it isn't needed.

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SWIFT_BIN_DIR="$(dirname "$(xcrun --find swift)")"
TESTING_PLUGIN_DIR="$SWIFT_BIN_DIR/../lib/swift/host/plugins/testing"

PLUGIN_ARGS=()
if [ -d "$TESTING_PLUGIN_DIR" ]; then
  PLUGIN_ARGS=(-Xswiftc -plugin-path -Xswiftc "$(cd "$TESTING_PLUGIN_DIR" && pwd)")
fi

swift test --package-path "$ROOT_DIR" ${PLUGIN_ARGS[@]+"${PLUGIN_ARGS[@]}"} "$@"
