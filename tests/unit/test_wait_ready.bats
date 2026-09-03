#!/usr/bin/env bats
# Behavior of _wait_for_custom_ready and the failure-log dump.
# sleep is stubbed to a no-op so tests run instantly; _is_healthy is stubbed
# to return controlled responses via a counter file.
load ../test_helper

setup() {
  TMPHOME="$(mktemp -d)"
  export TMPHOME
  export CANTON_DEVREL_DIR="$TMPHOME"
  export REPO_DIR
  mkdir -p "$TMPHOME/stubs"
  export PATH="$TMPHOME/stubs:$PATH"
  # Source the validator lib so we can call _wait_for_custom_ready directly.
  source "$REPO_DIR/scripts/lib/common.sh"
  source "$REPO_DIR/scripts/lib/validator.sh"
  # Stub sleep so the test runs in milliseconds, not minutes.
  eval 'sleep() { return 0; }'
}
teardown() { rm -rf "$TMPHOME"; }

@test "default timeout is 300s (60 attempts of 5s)" {
  # _is_healthy always fails → loop should run exactly DEFAULT_ATTEMPTS times.
  local hit_count_file="$TMPHOME/healthchecks"
  echo 0 >"$hit_count_file"
  eval '_is_healthy() {
    local n; n=$(cat "'"$hit_count_file"'"); n=$((n + 1)); echo "$n" >"'"$hit_count_file"'"
    return 1
  }'
  run _wait_for_custom_ready acme 5900
  [ "$status" -eq 1 ]
  local hits; hits=$(cat "$hit_count_file")
  [ "$hits" -eq 60 ]
}

@test "CANTON_DEVREL_VALIDATOR_READY_TIMEOUT_S overrides the default" {
  export CANTON_DEVREL_VALIDATOR_READY_TIMEOUT_S=30
  local hit_count_file="$TMPHOME/healthchecks"
  echo 0 >"$hit_count_file"
  eval '_is_healthy() {
    local n; n=$(cat "'"$hit_count_file"'"); n=$((n + 1)); echo "$n" >"'"$hit_count_file"'"
    return 1
  }'
  run _wait_for_custom_ready acme 5900
  [ "$status" -eq 1 ]
  local hits; hits=$(cat "$hit_count_file")
  # 30s / 5s = 6 attempts
  [ "$hits" -eq 6 ]
  unset CANTON_DEVREL_VALIDATOR_READY_TIMEOUT_S
}

@test "returns 0 as soon as readyz returns healthy" {
  export CANTON_DEVREL_VALIDATOR_READY_TIMEOUT_S=300
  local hit_count_file="$TMPHOME/healthchecks"
  echo 0 >"$hit_count_file"
  # Healthy on the 3rd call.
  eval '_is_healthy() {
    local n; n=$(cat "'"$hit_count_file"'"); n=$((n + 1)); echo "$n" >"'"$hit_count_file"'"
    [ "$n" -ge 3 ]
  }'
  run _wait_for_custom_ready acme 5900
  [ "$status" -eq 0 ]
  local hits; hits=$(cat "$hit_count_file")
  [ "$hits" -eq 3 ]
}

@test "prints a progress line at least every ~30s during the wait" {
  export CANTON_DEVREL_VALIDATOR_READY_TIMEOUT_S=60
  eval '_is_healthy() { return 1; }'
  run _wait_for_custom_ready acme 5900
  [ "$status" -eq 1 ]
  # Expect at least one progress line. Match the keyword we'll emit.
  echo "$output" | grep -q "still waiting"
}

@test "_dump_failure_logs writes a file that survives _undo's rm -rf" {
  # Stub docker so the dump call doesn't need a real daemon.
  stub_docker
  _dump_failure_logs acme
  # Path is at the top of CANTON_DEVREL_DIR so it isn't wiped by the rollback
  # that does `rm -rf validators/<name>/`.
  [ -f "$TMPHOME/last-validator-add-failure-acme.log" ]
}
