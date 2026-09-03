#!/usr/bin/env bats
load ../test_helper

@test "TMPHOME is created and isolated" {
  [ -d "$TMPHOME" ]
  [ "$CANTON_DEVREL_DIR" = "$TMPHOME" ]
}

@test "stub_docker intercepts docker calls" {
  stub_docker
  docker compose ls
  grep -q "compose ls" "$TMPHOME/docker-calls"
}
