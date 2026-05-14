#!/usr/bin/env bash
# Verb implementations for `canton devrel validator <verb>`.
[[ -n "${_VALIDATOR_SH_LOADED:-}" ]] && return; _VALIDATOR_SH_LOADED=1

# All sibling libs live in the same directory.
LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$LIB_DIR/common.sh"
source "$LIB_DIR/registry.sh"
source "$LIB_DIR/portalloc.sh"
source "$LIB_DIR/validate_name.sh"
source "$LIB_DIR/customenv.sh"
source "$LIB_DIR/nginxcustom.sh"
source "$LIB_DIR/compose.sh"

# Built-in port bases (fixed by bundle).
_builtin_port_base() {
  case "$1" in
    sv)           echo 4900 ;;
    app-provider) echo 3900 ;;
    app-user)     echo 2900 ;;
    *)            return 1 ;;
  esac
}

_builtin_wallet_url() {
  case "$1" in
    sv)           echo "http://wallet.localhost:4000" ;;
    app-provider) echo "http://wallet.localhost:3000" ;;
    app-user)     echo "http://wallet.localhost:2000" ;;
  esac
}

_health_check_url() {
  local entry="$1"
  local name port_base type
  name=$(echo "$entry" | jq -r .name)
  type=$(echo "$entry" | jq -r .type)
  if [ "$type" = "custom" ]; then
    port_base=$(echo "$entry" | jq -r .port_base)
    echo "http://localhost:$((port_base + 3))/api/validator/readyz"
  else
    port_base=$(_builtin_port_base "$name") || return 1
    echo "http://localhost:$((port_base + 3))/api/validator/readyz"
  fi
}

_is_healthy() {
  local url="$1"
  curl -fs --max-time 2 "$url" >/dev/null 2>&1
}

validator_list() {
  print_header "Validators"
  printf "  %-16s %-8s %-8s %-10s %s\n" NAME TYPE INTENT HEALTH WALLET
  # Always show sv first (infra).
  local sv_url; sv_url="http://localhost:4903/api/validator/readyz"
  local sv_health=DOWN
  _is_healthy "$sv_url" && sv_health=UP
  printf "  %-16s %-8s %-8s %-10s %s\n" sv infra always "$sv_health" "http://wallet.localhost:4000"

  registry_read | jq -c '.validators[]' | while read -r entry; do
    local name type running url health wallet
    name=$(echo "$entry" | jq -r .name)
    type=$(echo "$entry" | jq -r .type)
    running=$(echo "$entry" | jq -r .running)
    url=$(_health_check_url "$entry")
    health=DOWN; _is_healthy "$url" && health=UP
    if [ "$type" = "custom" ]; then
      wallet="http://wallet.$name.localhost:5000"
    else
      wallet=$(_builtin_wallet_url "$name")
    fi
    printf "  %-16s %-8s %-8s %-10s %s\n" "$name" "$type" "$running" "$health" "$wallet"
  done
}

validator_info() {
  local name="$1"
  if [ "$name" = "sv" ]; then
    print_header "sv (infrastructure)"
    echo "  Wallet:        http://wallet.localhost:4000"
    echo "  JSON API:      http://localhost:4975"
    echo "  Ledger API:    localhost:4901 (gRPC)"
    echo "  Validator API: http://localhost:4903"
    return 0
  fi
  local entry
  if ! entry=$(registry_get "$name"); then
    print_error "no such validator '$name'; run \`canton devrel validator list\`"
    return 1
  fi
  local type port_base party_hint
  type=$(echo "$entry" | jq -r .type)
  party_hint=$(echo "$entry" | jq -r .party_hint)
  if [ "$type" = "custom" ]; then
    port_base=$(echo "$entry" | jq -r .port_base)
    print_header "$name (custom)"
    echo "  Party hint:    $party_hint"
    echo "  Wallet:        http://wallet.$name.localhost:5000"
    echo "  JSON API:      http://localhost:$((port_base + 75))"
    echo "  Ledger API:    localhost:$((port_base + 1)) (gRPC)"
    echo "  Validator API: http://localhost:$((port_base + 3))"
  else
    port_base=$(_builtin_port_base "$name")
    print_header "$name (built-in)"
    echo "  Wallet:        $(_builtin_wallet_url "$name")"
    echo "  JSON API:      http://localhost:$((port_base + 75))"
    echo "  Ledger API:    localhost:$((port_base + 1)) (gRPC)"
    echo "  Validator API: http://localhost:$((port_base + 3))"
  fi
}
