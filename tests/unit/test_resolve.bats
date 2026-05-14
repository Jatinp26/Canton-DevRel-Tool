#!/usr/bin/env bats
load ../test_helper

setup() {
  TMPHOME="$(mktemp -d)"
  export CANTON_DEVREL_DIR="$TMPHOME"
  source "$REPO_DIR/scripts/lib/registry.sh"
  source "$REPO_DIR/scripts/lib/resolve.sh"
}
teardown() { rm -rf "$TMPHOME"; }

# helper to extract a single line from `output`
field() { echo "$output" | grep -E "^$1=" | cut -d= -f2-; }

@test "no flags, empty registry, no DEFAULT_VALIDATORS → app-provider only" {
  unset DEFAULT_VALIDATORS
  run resolve_active_set
  [ "$status" -eq 0 ]
  [ "$(field SV_PROFILE)" = "on" ]
  [ "$(field APP_PROVIDER_PROFILE)" = "on" ]
  [ "$(field APP_USER_PROFILE)" = "off" ]
  [ "$(field CUSTOMS)" = "" ]
}

@test "no flags, registry has running customs → those plus running builtins" {
  registry_with_lock registry_upsert_validator app-provider builtin "" "" true
  registry_with_lock registry_upsert_validator acme         custom  5900 acme-validator-1 true
  run resolve_active_set
  [ "$status" -eq 0 ]
  [ "$(field APP_PROVIDER_PROFILE)" = "on" ]
  [ "$(field APP_USER_PROFILE)" = "off" ]
  [ "$(field CUSTOMS)" = "acme" ]
}

@test "no flags, DEFAULT_VALIDATORS=app-user,acme used when registry empty" {
  # Pre-register acme so _validate_names recognises it; running=false so the
  # registry-running fallback is skipped and DEFAULT_VALIDATORS is exercised.
  registry_with_lock registry_upsert_validator acme custom 5900 acme-validator-1 false
  export DEFAULT_VALIDATORS=app-user,acme
  run resolve_active_set
  [ "$(field APP_PROVIDER_PROFILE)" = "off" ]
  [ "$(field APP_USER_PROFILE)" = "on" ]
  [ "$(field CUSTOMS)" = "acme" ]
}

@test "--absolute app-provider overrides everything else" {
  registry_with_lock registry_upsert_validator app-user builtin "" "" true
  export DEFAULT_VALIDATORS=app-user,acme
  run resolve_active_set --absolute app-provider
  [ "$(field APP_PROVIDER_PROFILE)" = "on" ]
  [ "$(field APP_USER_PROFILE)" = "off" ]
  [ "$(field CUSTOMS)" = "" ]
}

@test "--with app-user adds on top of resolved set" {
  run resolve_active_set --with app-user
  [ "$(field APP_PROVIDER_PROFILE)" = "on" ]
  [ "$(field APP_USER_PROFILE)" = "on" ]
}

@test "--without app-provider removes from resolved set" {
  run resolve_active_set --without app-provider
  [ "$(field APP_PROVIDER_PROFILE)" = "off" ]
  [ "$(field APP_USER_PROFILE)" = "off" ]
}

@test "rejects sv in --absolute" {
  run resolve_active_set --absolute sv,app-user
  [ "$status" -ne 0 ]
  [[ "$output" == *"sv is infrastructure"* ]]
}

@test "rejects sv in --with" {
  run resolve_active_set --with sv
  [ "$status" -ne 0 ]
}

@test "rejects mixing --absolute with --with" {
  run resolve_active_set --absolute app-provider --with app-user
  [ "$status" -ne 0 ]
  [[ "$output" == *"absolute"* ]]
}

@test "unknown name in --absolute errors" {
  # No registry entry, not a built-in → unknown.
  run resolve_active_set --absolute mystery
  [ "$status" -ne 0 ]
  [[ "$output" == *"no such validator"* ]]
}
