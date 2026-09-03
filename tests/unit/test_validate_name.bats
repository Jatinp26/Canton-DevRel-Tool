#!/usr/bin/env bats
load ../test_helper

setup() {
  TMPHOME="$(mktemp -d)"
  export CANTON_DEVREL_DIR="$TMPHOME"
  source "$REPO_DIR/scripts/lib/validate_name.sh"
}
teardown() { rm -rf "$TMPHOME"; }

@test "accepts a simple lowercase name" {
  run validate_validator_name "acme"
  [ "$status" -eq 0 ]
}

@test "accepts hyphens and digits" {
  run validate_validator_name "acme-1"
  [ "$status" -eq 0 ]
}

@test "rejects names starting with a digit" {
  run validate_validator_name "1acme"
  [ "$status" -ne 0 ]
  [[ "$output" == *"must match"* ]]
}

@test "rejects uppercase" {
  run validate_validator_name "Acme"
  [ "$status" -ne 0 ]
}

@test "rejects names too short" {
  run validate_validator_name "a"
  [ "$status" -ne 0 ]
}

@test "rejects names too long (>31 chars)" {
  run validate_validator_name "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"  # 33
  [ "$status" -ne 0 ]
}

@test "rejects reserved names" {
  for name in sv app-provider app-user postgres splice canton nginx scan keycloak; do
    run validate_validator_name "$name"
    [ "$status" -ne 0 ]
    [[ "$output" == *"reserved"* ]]
  done
}
