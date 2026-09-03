#!/usr/bin/env bats
load ../test_helper

setup() {
  TMPHOME="$(mktemp -d)"
  export CANTON_DEVREL_DIR="$TMPHOME"
  source "$REPO_DIR/scripts/lib/registry.sh"
}
teardown() { rm -rf "$TMPHOME"; }

@test "read of missing registry returns empty skeleton" {
  run registry_read
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.version == 1 and (.validators | length) == 0'
}

@test "upsert inserts a new validator entry" {
  registry_with_lock registry_upsert_validator acme custom 5900 acme-validator-1 false
  registry_read | jq -e '.validators[] | select(.name=="acme" and .type=="custom" and .port_base==5900 and .party_hint=="acme-validator-1" and .running==false)'
}

@test "upsert updates an existing entry by name" {
  registry_with_lock registry_upsert_validator acme custom 5900 acme-validator-1 false
  registry_with_lock registry_upsert_validator acme custom 5900 acme-validator-1 true
  local count
  count=$(registry_read | jq '[.validators[] | select(.name=="acme")] | length')
  [ "$count" -eq 1 ]
  registry_read | jq -e '.validators[] | select(.name=="acme" and .running==true)'
}

@test "remove deletes a validator" {
  registry_with_lock registry_upsert_validator acme custom 5900 acme-validator-1 false
  registry_with_lock registry_remove_validator acme
  local count
  count=$(registry_read | jq '[.validators[] | select(.name=="acme")] | length')
  [ "$count" -eq 0 ]
}

@test "concurrent writers serialize under lock" {
  for i in 1 2 3 4 5; do
    registry_with_lock registry_upsert_validator "v$i" custom $((5900 + 1000*i)) "v$i-validator-1" false &
  done
  wait
  local count
  count=$(registry_read | jq '.validators | length')
  [ "$count" -eq 5 ]
}

@test "registry_get returns a single entry as JSON" {
  registry_with_lock registry_upsert_validator acme custom 5900 acme-validator-1 true
  run registry_get acme
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.name == "acme" and .port_base == 5900'
}

@test "registry_get returns non-zero for missing entry" {
  run registry_get acme
  [ "$status" -ne 0 ]
}

@test "registry_list_running returns only running validators" {
  registry_with_lock registry_upsert_validator acme custom 5900 acme-validator-1 true
  registry_with_lock registry_upsert_validator bob  custom 6900 bob-validator-1  false
  run registry_list_running
  [ "$status" -eq 0 ]
  [[ "$output" == *"acme"* ]]
  [[ "$output" != *"bob"* ]]
}
