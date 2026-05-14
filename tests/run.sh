#!/usr/bin/env bash
# Run the bats test suites. Vendored bats-core under tests/.bats on first run.
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BATS_DIR="$REPO_DIR/tests/.bats"

if [ ! -x "$BATS_DIR/bin/bats" ]; then
  echo "Installing bats-core into $BATS_DIR..."
  git clone --depth 1 https://github.com/bats-core/bats-core.git "$BATS_DIR" >/dev/null
fi

SUITE="${1:-unit}"
exec "$BATS_DIR/bin/bats" "$REPO_DIR/tests/$SUITE"
