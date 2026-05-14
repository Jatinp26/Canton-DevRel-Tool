#!/usr/bin/env bats
# The custom-validator stack inherits no host port mappings: the bundle's nginx
# (the only host-bound service) is unbound by attach-localnet.overlay.yaml to
# avoid 80:80 collisions across multiple validator-<name> projects. The overlay
# must re-bind the validator backend + participant ledger ports so the host can
# reach /api/validator/readyz, the gRPC ledger API, and the JSON ledger API at
# the host ports `validator_info` advertises.
load ../test_helper

setup() {
  OVERLAY="$REPO_DIR/overlays/attach-localnet.overlay.yaml"
}

@test "overlay binds host VALIDATOR_API_PORT to validator:5003" {
  grep -qE '^\s*-\s*"?\$\{VALIDATOR_API_PORT\}:5003"?' "$OVERLAY"
}

@test "overlay binds host LEDGER_API_PORT to participant:5001 (gRPC)" {
  grep -qE '^\s*-\s*"?\$\{LEDGER_API_PORT\}:5001"?' "$OVERLAY"
}

@test "overlay binds host JSON_API_PORT to participant:7575 (JSON)" {
  grep -qE '^\s*-\s*"?\$\{JSON_API_PORT\}:7575"?' "$OVERLAY"
}

@test "overlay still unbinds nginx host ports (avoid :80 collision)" {
  # The unbind is required to allow multiple validator-<name> projects to coexist.
  grep -qE 'ports:\s*!reset\s*\[\]' "$OVERLAY"
}
