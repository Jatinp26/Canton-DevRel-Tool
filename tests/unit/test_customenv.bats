#!/usr/bin/env bats
load ../test_helper

setup() {
  TMPHOME="$(mktemp -d)"
  export CANTON_DEVREL_DIR="$TMPHOME"
  export IMAGE_TAG=1.2.3
  # Fake bundle VERSION so render_custom_env can derive IMAGE_TAG when caller doesn't set it.
  export BUNDLE_DIR="$TMPHOME/bundle"
  mkdir -p "$BUNDLE_DIR/splice-node"
  echo "0.5.18" >"$BUNDLE_DIR/splice-node/VERSION"
  source "$REPO_DIR/scripts/lib/customenv.sh"
}
teardown() { rm -rf "$TMPHOME"; }

@test "render_custom_env writes load-bearing keys" {
  render_custom_env acme 5900 acme-validator-1 "fake-secret-token"
  local f="$TMPHOME/validators/acme/env"
  [ -f "$f" ]
  grep -q "IMAGE_TAG=1.2.3" "$f"
  grep -q 'SPONSOR_SV_ADDRESS=http://splice:5014' "$f"
  grep -q 'SCAN_ADDRESS=http://splice:5012' "$f"
  grep -q '^ONBOARDING_SECRET="fake-secret-token"$' "$f"
  grep -q "PARTY_HINT=acme-validator-1" "$f"
  grep -q "PORT_BASE=5900" "$f"
  grep -q "LEDGER_API_PORT=5901" "$f"
  grep -q "VALIDATOR_API_PORT=5903" "$f"
  grep -q "JSON_API_PORT=5975" "$f"
}

@test "render_custom_env is idempotent (rewrites cleanly)" {
  render_custom_env acme 5900 acme-validator-1 "fake-secret-token"
  render_custom_env acme 5900 acme-validator-1 "fake-secret-token-2"
  local n
  n=$(grep -c "PORT_BASE=" "$TMPHOME/validators/acme/env")
  [ "$n" -eq 1 ]
}

@test "render_custom_env defaults IMAGE_REPO to ghcr.io (matches bundle/localnet)" {
  unset IMAGE_REPO
  render_custom_env acme 5900 acme-validator-1 "fake-secret-token"
  grep -q "^IMAGE_REPO=ghcr.io/digital-asset/decentralized-canton-sync/docker/$" \
    "$TMPHOME/validators/acme/env"
}

@test "render_custom_env honors caller-provided IMAGE_REPO" {
  export IMAGE_REPO="example.com/repo/"
  render_custom_env acme 5900 acme-validator-1 "fake-secret-token"
  grep -q "^IMAGE_REPO=example.com/repo/$" "$TMPHOME/validators/acme/env"
  unset IMAGE_REPO
}

@test "render_custom_env derives IMAGE_TAG from bundle VERSION when caller hasn't set one" {
  unset IMAGE_TAG
  render_custom_env acme 5900 acme-validator-1 "fake-secret-token"
  grep -q "^IMAGE_TAG=0.5.18$" "$TMPHOME/validators/acme/env"
}

@test "render_custom_env writes PARTICIPANT_IDENTIFIER (defaults to party_hint, mirroring bundle start.sh)" {
  # Bundle's validator/.env leaves PARTICIPANT_IDENTIFIER empty. compose.yaml
  # passes it through as SPLICE_APP_VALIDATOR_PARTICIPANT_IDENTIFIER. If empty,
  # the validator crashes with "Daml-LF Party is empty" during NodeInitializer.
  render_custom_env acme 5900 acme-validator-1 "fake-secret-token"
  grep -q "^PARTICIPANT_IDENTIFIER=acme-validator-1$" "$TMPHOME/validators/acme/env"
}

@test "render_custom_env writes ONBOARDING_SECRET from the 4th argument" {
  # Bundle's SV only knows two pre-shared secrets (APP_PROVIDER/APP_USER).
  # For custom validators, validator_add fetches a fresh secret from the SV's
  # DevNet prepare endpoint and threads it through here. An empty secret would
  # get rejected as "Unknown secret" by the SV during onboarding.
  render_custom_env acme 5900 acme-validator-1 "eyJzcG9uc29yaW5nU3Yi=="
  grep -q '^ONBOARDING_SECRET="eyJzcG9uc29yaW5nU3Yi=="$' "$TMPHOME/validators/acme/env"
}

@test "render_custom_env writes SPLICE_APP_UI_* defaults matching localnet common.env" {
  render_custom_env acme 5900 acme-validator-1 "fake-secret-token"
  local f="$TMPHOME/validators/acme/env"
  grep -q '^SPLICE_APP_UI_NETWORK_NAME=Splice$' "$f"
  grep -q '^SPLICE_APP_UI_AMULET_NAME=Amulet$' "$f"
  grep -q '^SPLICE_APP_UI_AMULET_NAME_ACRONYM=AMT$' "$f"
  grep -q '^SPLICE_APP_UI_NAME_SERVICE_NAME=Amulet Name Service$' "$f"
  grep -q '^SPLICE_APP_UI_NAME_SERVICE_NAME_ACRONYM=ANS$' "$f"
  grep -q '^SPLICE_APP_UI_NETWORK_FAVICON_URL=' "$f"
}
