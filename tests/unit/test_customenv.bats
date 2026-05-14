#!/usr/bin/env bats
load ../test_helper

setup() {
  TMPHOME="$(mktemp -d)"
  export CANTON_DEVREL_DIR="$TMPHOME"
  export IMAGE_TAG=1.2.3
  source "$REPO_DIR/scripts/lib/customenv.sh"
}
teardown() { rm -rf "$TMPHOME"; }

@test "render_custom_env writes load-bearing keys" {
  render_custom_env acme 5900 acme-validator-1
  local f="$TMPHOME/validators/acme/env"
  [ -f "$f" ]
  grep -q "IMAGE_TAG=1.2.3" "$f"
  grep -q 'SPONSOR_SV_ADDRESS=http://splice:5014' "$f"
  grep -q 'SCAN_ADDRESS=http://splice:5012' "$f"
  grep -q 'ONBOARDING_SECRET=""' "$f"
  grep -q "PARTY_HINT=acme-validator-1" "$f"
  grep -q "PORT_BASE=5900" "$f"
  grep -q "LEDGER_API_PORT=5901" "$f"
  grep -q "VALIDATOR_API_PORT=5903" "$f"
  grep -q "JSON_API_PORT=5975" "$f"
}

@test "render_custom_env is idempotent (rewrites cleanly)" {
  render_custom_env acme 5900 acme-validator-1
  render_custom_env acme 5900 acme-validator-1
  local n
  n=$(grep -c "PORT_BASE=" "$TMPHOME/validators/acme/env")
  [ "$n" -eq 1 ]
}
