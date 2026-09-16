#!/usr/bin/env bash
# Builds the TypeScript example against the plugin checked out one directory up.
# The work happens in scripts/build-example.sh; see there and in README.md.
set -euo pipefail
exec "$(dirname "${BASH_SOURCE[0]}")/../scripts/build-example.sh" "$(dirname "${BASH_SOURCE[0]}")" "$@"
