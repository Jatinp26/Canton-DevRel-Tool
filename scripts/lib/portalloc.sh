#!/usr/bin/env bash
# Port-base allocation. Pure functions (probe is overridable for tests).
[[ -n "${_PORTALLOC_SH_LOADED:-}" ]] && return; _PORTALLOC_SH_LOADED=1

PORT_BASE_START=5900
PORT_BASE_STEP=1000
PORT_BASE_MAX_RETRIES=10

# Derived host ports for a given port_base.
# Spec §6.1:
#   N+1   ledger API (gRPC)
#   N+3   validator API / readyz
#   N+75  JSON API
#   (N-900 wallet UI host port is NOT bound for customs; nginx serves :5000.)
_derived_ports() {
  local n="$1"
  echo $((n + 1))
  echo $((n + 3))
  echo $((n + 75))
}

# Override in tests; default uses /dev/tcp.
port_in_use() {
  local p="$1"
  (exec 3<>/dev/tcp/127.0.0.1/"$p") 2>/dev/null && { exec 3<&- 3>&-; return 0; } || return 1
}

_all_derived_free() {
  local base="$1"
  local p
  while read -r p; do
    if port_in_use "$p"; then return 1; fi
  done < <(_derived_ports "$base")
  return 0
}

allocate_port_base() {
  local base=$PORT_BASE_START
  local tries=0
  while [ "$tries" -lt "$PORT_BASE_MAX_RETRIES" ]; do
    if _all_derived_free "$base"; then
      echo "$base"
      return 0
    fi
    base=$((base + PORT_BASE_STEP))
    tries=$((tries + 1))
  done
  echo "no free port range found near $PORT_BASE_START — close conflicting processes or pass --port-base N" >&2
  return 1
}

validate_explicit_port_base() {
  local base="$1"
  if [[ ! "$base" =~ ^[0-9]+$ ]]; then
    echo "--port-base must be a positive integer" >&2; return 1
  fi
  if (( base % 1000 != 900 )); then
    echo "--port-base must end in 900 (e.g. 5900, 6900, 7900)" >&2; return 1
  fi
  local p
  while read -r p; do
    if port_in_use "$p"; then
      echo "derived port $p is in use; pick a different --port-base" >&2; return 1
    fi
  done < <(_derived_ports "$base")
  return 0
}
