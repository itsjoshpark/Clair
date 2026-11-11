#!/bin/bash
# Compiles the Swift tools in this directory into build/probe/bin/ and prints
# that directory. The other probe scripts do this themselves when needed.

set -euo pipefail
# shellcheck source=tests/probe/lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"

build_tools
echo "$bin"
