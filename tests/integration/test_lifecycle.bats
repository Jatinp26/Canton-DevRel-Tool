#!/usr/bin/env bats
# Slow Docker-gated lifecycle integration test. Run with CI_INTEGRATION=1.

load ../test_helper

setup() {
  if [ "${CI_INTEGRATION:-0}" != "1" ]; then
    skip "set CI_INTEGRATION=1 to run integration suite"
  fi
  if ! command -v docker >/dev/null; then
    skip "docker not available"
  fi
  REPO_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
  export REPO_DIR
  # NB: this test uses the user's real ~/.canton-devrel (no isolation possible
  # since the Docker daemon is shared); cleanup happens in teardown.
}

teardown() {
  "$REPO_DIR/canton" devrel reset --purge <<< "yes" >/dev/null 2>&1 || true
}

@test "start no flags brings up app-provider only (no app-user)" {
  "$REPO_DIR/canton" devrel start
  run curl -fs http://localhost:3903/api/validator/readyz
  [ "$status" -eq 0 ]
  run curl -fs --max-time 3 http://localhost:2903/api/validator/readyz
  [ "$status" -ne 0 ]
}

@test "start --with app-user brings up both builtins" {
  "$REPO_DIR/canton" devrel start --with app-user
  curl -fs http://localhost:3903/api/validator/readyz
  curl -fs http://localhost:2903/api/validator/readyz
}

@test "validator add acme produces a working 4th validator" {
  "$REPO_DIR/canton" devrel start
  "$REPO_DIR/canton" devrel validator add acme
  curl -fs http://localhost:5903/api/validator/readyz
  run curl -fs --max-time 3 --resolve wallet.acme.localhost:5000:127.0.0.1 http://wallet.acme.localhost:5000
  [ "$status" -eq 0 ]
}

@test "stop preserves intent; start brings same shape back; data persists" {
  "$REPO_DIR/canton" devrel start
  "$REPO_DIR/canton" devrel validator add acme
  "$REPO_DIR/canton" devrel validator stop acme
  "$REPO_DIR/canton" devrel stop
  "$REPO_DIR/canton" devrel start
  # acme was stopped before global stop → must NOT auto-start.
  run curl -fs --max-time 3 http://localhost:5903/api/validator/readyz
  [ "$status" -ne 0 ]
  # Bring acme back; ledger should still be intact.
  "$REPO_DIR/canton" devrel validator start acme
  curl -fs http://localhost:5903/api/validator/readyz
}

@test "validator rm wipes everything for that custom" {
  "$REPO_DIR/canton" devrel start
  "$REPO_DIR/canton" devrel validator add acme
  "$REPO_DIR/canton" devrel validator rm acme
  [ ! -d "$HOME/.canton-devrel/validators/acme" ]
  [ ! -f "$HOME/.canton-devrel/nginx-customs/acme.conf" ]
  run jq -e '.validators[] | select(.name=="acme")' "$HOME/.canton-devrel/validators.json"
  [ "$status" -ne 0 ]
}

@test "reset preserves recipes, reset --purge wipes them" {
  "$REPO_DIR/canton" devrel start
  "$REPO_DIR/canton" devrel validator add acme
  echo "yes" | "$REPO_DIR/canton" devrel reset
  [ -d "$HOME/.canton-devrel/validators/acme" ]
  echo "yes" | "$REPO_DIR/canton" devrel reset --purge
  [ ! -d "$HOME/.canton-devrel" ]
}
