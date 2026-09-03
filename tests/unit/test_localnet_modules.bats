#!/usr/bin/env bats
# LocalNet is assembled from cn-quickstart compose modules. These tests verify
# infra_compose_argv wires the right modules/profiles/env-files for each mode.
load ../test_helper

# Create minimal fixture module files so the on-disk guards in infra_compose_argv fire.
_make_fixtures() {
  local m="$CANTON_DEVREL_DIR/modules"
  mkdir -p "$m/localnet/env" "$m/splice-onboarding" "$m/keycloak" "$m/pqs"
  : > "$m/localnet/compose.yaml"
  : > "$m/localnet/compose.env"
  : > "$m/localnet/env/common.env"
  : > "$m/localnet/resource-constraints.yaml"
  : > "$m/splice-onboarding/compose.yaml"
  : > "$m/keycloak/compose.yaml"
  : > "$m/keycloak/compose.env"
  : > "$m/pqs/compose.yaml"
  : > "$m/pqs/compose.env"
}

_argv() {
  source "$REPO_DIR/scripts/lib/common.sh"
  source "$REPO_DIR/scripts/lib/compose.sh"
  mapfile -t argv < <(infra_compose_argv "${1:-}")
  printf '%s\n' "${argv[@]}"
}

@test "base assembly always includes localnet + splice-onboarding compose files" {
  _make_fixtures
  run bash -c "$(declare -f _argv); _argv"
  echo "$output" | grep -q 'modules/localnet/compose.yaml'
  echo "$output" | grep -q 'modules/splice-onboarding/compose.yaml'
}

@test "base assembly includes sv/app-provider/app-user/swagger-ui profiles" {
  _make_fixtures
  run bash -c "$(declare -f _argv); _argv"
  echo "$output" | grep -qx -- '--profile' # sanity: profiles present
  printf '%s' "$output" | grep -qz 'sv'
  echo "$output" | grep -q 'app-provider'
  echo "$output" | grep -q 'app-user'
  echo "$output" | grep -q 'swagger-ui'
}

@test "default (no auth) does NOT include keycloak" {
  _make_fixtures
  run bash -c "$(declare -f _argv); _argv"
  ! echo "$output" | grep -q 'keycloak/compose.yaml'
  ! echo "$output" | grep -qx -- 'keycloak'
}

@test "AUTH_MODE=oauth2 includes keycloak compose, env-file, and profile" {
  _make_fixtures
  run bash -c "$(declare -f _argv); export AUTH_MODE=oauth2; _argv"
  echo "$output" | grep -q 'keycloak/compose.yaml'
  echo "$output" | grep -q 'keycloak/compose.env'
  echo "$output" | grep -qx 'keycloak'
}

@test "keycloak compose.env is layered AFTER localnet common.env (so it can override auth env)" {
  _make_fixtures
  run bash -c "$(declare -f _argv); export AUTH_MODE=oauth2; _argv"
  local common_idx kc_idx
  common_idx=$(echo "$output" | grep -n 'localnet/env/common.env' | head -1 | cut -d: -f1)
  kc_idx=$(echo "$output" | grep -n 'keycloak/compose.env' | head -1 | cut -d: -f1)
  [ -n "$common_idx" ] && [ -n "$kc_idx" ]
  [ "$kc_idx" -gt "$common_idx" ]
}

@test "PQS_ENABLED=on includes pqs compose and pqs-app-provider profile" {
  _make_fixtures
  run bash -c "$(declare -f _argv); export PQS_ENABLED=on; _argv"
  echo "$output" | grep -q 'pqs/compose.yaml'
  echo "$output" | grep -q 'pqs-app-provider'
}

@test "PQS opt-in: default run does NOT include pqs" {
  _make_fixtures
  run bash -c "$(declare -f _argv); _argv"
  ! echo "$output" | grep -q 'pqs/compose.yaml'
}

@test "--all force-includes keycloak + pqs when present, regardless of mode" {
  _make_fixtures
  run bash -c "$(declare -f _argv); _argv --all"
  echo "$output" | grep -q 'keycloak/compose.yaml'
  echo "$output" | grep -q 'pqs/compose.yaml'
}

@test "APP_USER_PROFILE=off drops the app-user profile" {
  _make_fixtures
  run bash -c "$(declare -f _argv); export APP_USER_PROFILE=off; _argv"
  ! echo "$output" | grep -qx 'app-user'
}
