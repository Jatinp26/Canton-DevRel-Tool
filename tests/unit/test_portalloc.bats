#!/usr/bin/env bats
load ../test_helper

setup() {
  TMPHOME="$(mktemp -d)"
  export CANTON_DEVREL_DIR="$TMPHOME"
  # Override TCP probe with a stub that reads $TMPHOME/busy-ports (newline-separated).
  source "$REPO_DIR/scripts/lib/portalloc.sh"
  port_in_use() {
    local p="$1"
    grep -qx "$p" "$TMPHOME/busy-ports" 2>/dev/null
  }
}
teardown() { rm -rf "$TMPHOME"; }

@test "allocates 5900 when all derived ports free" {
  : > "$TMPHOME/busy-ports"
  run allocate_port_base
  [ "$status" -eq 0 ]
  [ "$output" = "5900" ]
}

@test "bumps to 6900 when 5900's ledger port is busy" {
  echo 5901 > "$TMPHOME/busy-ports"
  run allocate_port_base
  [ "$status" -eq 0 ]
  [ "$output" = "6900" ]
}

@test "fails after 10 retries" {
  for n in 5901 6901 7901 8901 9901 10901 11901 12901 13901 14901; do
    echo "$n" >> "$TMPHOME/busy-ports"
  done
  run allocate_port_base
  [ "$status" -ne 0 ]
  [[ "$output" == *"no free port range"* ]]
}

@test "validate_explicit_port_base accepts 5900" {
  : > "$TMPHOME/busy-ports"
  run validate_explicit_port_base 5900
  [ "$status" -eq 0 ]
}

@test "validate_explicit_port_base rejects 5950 (must end in 900)" {
  run validate_explicit_port_base 5950
  [ "$status" -ne 0 ]
  [[ "$output" == *"must end in 900"* ]]
}

@test "validate_explicit_port_base rejects 5900 when a derived port is busy" {
  echo 5975 > "$TMPHOME/busy-ports"
  run validate_explicit_port_base 5900
  [ "$status" -ne 0 ]
  [[ "$output" == *"in use"* ]]
}
