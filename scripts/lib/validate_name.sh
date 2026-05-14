#!/usr/bin/env bash
# Validator-name validation. Pure function.
[[ -n "${_VALIDATE_NAME_SH_LOADED:-}" ]] && return; _VALIDATE_NAME_SH_LOADED=1

# Names reserved by infra services or built-in validators.
RESERVED_NAMES=(sv app-provider app-user postgres splice canton nginx scan keycloak)
NAME_REGEX='^[a-z][a-z0-9-]{1,30}$'

validate_validator_name() {
  local name="$1"
  if [[ ! "$name" =~ $NAME_REGEX ]]; then
    echo "name must match $NAME_REGEX (lowercase letter, then 1-30 of [a-z0-9-])" >&2
    return 1
  fi
  local r
  for r in "${RESERVED_NAMES[@]}"; do
    if [[ "$name" == "$r" ]]; then
      echo "name '$name' is reserved (infra or built-in); pick another" >&2
      return 1
    fi
  done
  return 0
}
