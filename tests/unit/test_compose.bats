#!/usr/bin/env bats
load ../test_helper

setup() {
  TMPHOME="$(mktemp -d)"
  export CANTON_DEVREL_DIR="$TMPHOME"
  export VALIDATOR_BUNDLE_DIR="$TMPHOME/bundle/validator"
  export LOCALNET_DIR="$TMPHOME/bundle/localnet"
  export OVERLAYS_DIR="$REPO_DIR/overlays"
  mkdir -p "$VALIDATOR_BUNDLE_DIR" "$LOCALNET_DIR"
  # Bundle .env that we expect custom_compose_argv to include.
  printf 'NGINX_VERSION=1.27.1\nSPLICE_DB_USER=cnadmin\n' >"$VALIDATOR_BUNDLE_DIR/.env"
  source "$REPO_DIR/scripts/lib/compose.sh"
}
teardown() { rm -rf "$TMPHOME"; }

@test "custom_compose_argv includes the bundle .env as --env-file" {
  mapfile -t argv < <(custom_compose_argv acme)
  # Must contain the bundle .env path right after an --env-file flag.
  local found=0 i
  for ((i=0; i<${#argv[@]}-1; i++)); do
    if [ "${argv[$i]}" = "--env-file" ] && [ "${argv[$((i+1))]}" = "$VALIDATOR_BUNDLE_DIR/.env" ]; then
      found=1
      break
    fi
  done
  [ "$found" -eq 1 ]
}

@test "custom_compose_argv places bundle .env before the rendered env (rendered overrides bundle)" {
  mapfile -t argv < <(custom_compose_argv acme)
  local rendered="$CANTON_DEVREL_DIR/validators/acme/env"
  local bundle="$VALIDATOR_BUNDLE_DIR/.env"
  local bundle_pos=-1 rendered_pos=-1 i
  for ((i=0; i<${#argv[@]}; i++)); do
    [ "${argv[$i]}" = "$bundle" ]   && bundle_pos=$i
    [ "${argv[$i]}" = "$rendered" ] && rendered_pos=$i
  done
  [ "$bundle_pos" -ge 0 ]
  [ "$rendered_pos" -ge 0 ]
  [ "$bundle_pos" -lt "$rendered_pos" ]
}

@test "custom_compose_argv still emits the project name validator-<name>" {
  mapfile -t argv < <(custom_compose_argv acme)
  local found=0 i
  for ((i=0; i<${#argv[@]}-1; i++)); do
    if [ "${argv[$i]}" = "-p" ] && [ "${argv[$((i+1))]}" = "validator-acme" ]; then
      found=1; break
    fi
  done
  [ "$found" -eq 1 ]
}
