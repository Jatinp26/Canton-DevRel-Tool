#!/usr/bin/env bats
# The bundle's localnet SV registers its scan URL in DsoRules as
# http://localhost:5012. That URL is unreachable from peer containers
# (e.g. a custom validator on the localnet network) because `localhost`
# inside the peer is its own loopback. The overlay below ships a patched
# app.conf that registers http://splice:5012 instead, so BftScanConnection
# from peer validators can reach the SV's scan service via Docker DNS.
load ../test_helper

setup() {
  SV_CONF="$REPO_DIR/overlays/splice-conf/sv-app.conf"
  OVERLAY="$REPO_DIR/overlays/sv-scan-url.overlay.yaml"
}

@test "patched SV app.conf sets scan.internal-url to splice:5012" {
  grep -qE '^\s*internal-url\s*=\s*"http://splice:5012"\s*$' "$SV_CONF"
}

@test "patched SV app.conf sets scan.public-url to splice:5012" {
  # Peer validators read public-url (not internal-url) from DsoRules via
  # BftScanConnection; both must point at the docker-DNS hostname for
  # peer-on-localnet reachability. Matches the bundle's own peer-mode SV
  # setup at docker-compose/sv/compose.yaml which patches both URLs.
  grep -qE '^\s*public-url\s*=\s*"http://splice:5012"\s*$' "$SV_CONF"
}

@test "patched SV app.conf no longer registers localhost:5012 in sv-apps.sv.scan" {
  # Spot-check: both URLs in the sv-apps.sv.scan block are now docker DNS.
  # Other localhost:5012 occurrences (e.g. SV-validator's own scan-client)
  # may remain because they correctly target the SV's own loopback.
  ! grep -qE '^\s*(public-url|internal-url)\s*=\s*"http://localhost:5012"' "$SV_CONF"
}

@test "compose overlay mounts our patched file over /app/sv/<profile>/app.conf" {
  grep -qE '\$\{OVERLAYS_DIR\}/splice-conf/sv-app\.conf:/app/sv/\$\{SV_PROFILE\}/app\.conf' "$OVERLAY"
}

@test "common.sh exports OVERLAYS_DIR so docker compose can interpolate it" {
  # Verify in a subshell that OVERLAYS_DIR is exported, not just shell-local.
  run bash -c "source $REPO_DIR/scripts/lib/common.sh && env | grep -E '^OVERLAYS_DIR='"
  [ "$status" -eq 0 ]
}

@test "infra_compose_argv includes the sv-scan-url overlay" {
  source "$REPO_DIR/scripts/lib/common.sh"
  source "$REPO_DIR/scripts/lib/compose.sh"
  mapfile -t argv < <(infra_compose_argv)
  printf '%s\n' "${argv[@]}" | grep -q 'sv-scan-url.overlay.yaml'
}
