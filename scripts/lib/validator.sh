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

# Mint a one-time onboarding secret from the SV's DevNet prepare endpoint.
# The bundle's SV hard-codes expected-validator-onboardings to just the two
# built-in (app-provider, app-user) secrets, so a custom validator that sends
# anything else — including an empty string — gets 401 "Unknown secret" during
# onboarding. SPLICE_SV_IS_DEVNET=true (our localnet's default) gates this
# endpoint open. The response body IS the opaque secret token (a base64 JSON
# envelope); the validator's start.sh passes it through to SPLICE_APP_VALIDATOR_
# ONBOARDING_SECRET, and the SV decodes it server-side. Do not parse.
_fetch_onboarding_secret() {
  local url="${SV_SPONSOR_HOST_URL:-http://sv.localhost:4000}/api/sv/v0/devnet/onboard/validator/prepare"
  local tmpfile http_code
  tmpfile=$(mktemp)
  if ! http_code=$(curl -sS --max-time 10 -X POST -o "$tmpfile" -w '%{http_code}' "$url" 2>>"$tmpfile.err"); then
    print_error "failed to reach SV at $url: $(cat "$tmpfile.err" 2>/dev/null)" >&2
    rm -f "$tmpfile" "$tmpfile.err"
    return 1
  fi
  if [ "$http_code" != "200" ]; then
    print_error "SV prepare endpoint returned HTTP $http_code: $(cat "$tmpfile")" >&2
    rm -f "$tmpfile" "$tmpfile.err"
    return 1
  fi
  if [ ! -s "$tmpfile" ]; then
    print_error "SV prepare endpoint returned an empty body" >&2
    rm -f "$tmpfile" "$tmpfile.err"
    return 1
  fi
  cat "$tmpfile"
  rm -f "$tmpfile" "$tmpfile.err"
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
      wallet="http://wallet.$name.localhost:5500"
    else
      wallet=$(_builtin_wallet_url "$name")
    fi
    [ "$health" = "DOWN" ] && wallet="—"
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
    echo "  Wallet:        http://wallet.$name.localhost:5500"
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

# Wait for the per-custom validator's readyz, up to 90s.
_wait_for_custom_ready() {
  local name="$1" port_base="$2"
  local url="http://localhost:$((port_base + 3))/api/validator/readyz"
  local attempts=0
  while [ "$attempts" -lt 18 ]; do  # 18 * 5s = 90s
    if _is_healthy "$url"; then return 0; fi
    sleep 5
    attempts=$((attempts + 1))
  done
  return 1
}

# Check `docker compose ls` for a phantom project of the same name.
_phantom_project_exists() {
  local name="$1"
  docker compose ls --format json 2>/dev/null \
    | jq -e --arg p "validator-$name" '.[] | select(.Name == $p)' >/dev/null
}

# Check infra (localnet stack's nginx container) is up.
_infra_running() {
  docker ps --format '{{.Names}}' 2>/dev/null | grep -qx nginx
}

validator_add() {
  local name=""
  local explicit_port_base=""
  while [ $# -gt 0 ]; do
    case "$1" in
      --port-base) explicit_port_base="$2"; shift 2 ;;
      -*) print_error "unknown flag: $1"; return 1 ;;
      *)  name="$1"; shift ;;
    esac
  done
  [ -z "$name" ] && { print_error "usage: validator add <name> [--port-base N]"; return 1; }

  # ── Pre-flight validation (no side effects yet) ──────────────────────────────
  validate_validator_name "$name" || return 1
  if registry_get "$name" >/dev/null 2>&1; then
    print_error "'$name' already exists; use \`validator start $name\`"; return 1
  fi
  if _phantom_project_exists "$name"; then
    print_error "compose project 'validator-$name' already exists; resolve manually then retry"
    return 1
  fi
  if [ -f "$CANTON_DEVREL_DIR/validators/$name/.add-failed" ]; then
    print_error "previous add for '$name' failed mid-rollback; run \`validator rm $name --force\`"
    return 1
  fi

  # Allocate port base.
  local port_base
  if [ -n "$explicit_port_base" ]; then
    validate_explicit_port_base "$explicit_port_base" || return 1
    port_base="$explicit_port_base"
  else
    port_base=$(allocate_port_base) || return 1
  fi
  local party_hint="${name}-validator-1"

  # Ensure infra is up; if not, bring it up.
  if ! _infra_running; then
    print_step "Infra not running — starting localnet first…"
    "$REPO_DIR/scripts/start.sh" || { print_error "could not start infra"; return 1; }
  fi

  # ── Side-effecting steps, each tracked for rollback ─────────────────────────
  ADD_STEPS=()
  _undo() {
    print_warning "Rolling back validator add for '$name'…"
    local step
    while [ "${#ADD_STEPS[@]}" -gt 0 ]; do
      step="${ADD_STEPS[-1]}"
      unset 'ADD_STEPS[-1]'
      case "$step" in
        registry)
          registry_with_lock registry_remove_validator "$name" || return 1 ;;
        envfile)
          rm -rf "$CANTON_DEVREL_DIR/validators/$name" ;;
        nginxconf)
          remove_nginx_conf "$name" ;;
        composeup)
          mapfile -t argv < <(custom_compose_argv "$name")
          "${argv[@]}" down -v >/dev/null 2>&1 || true ;;
        nginxreload)
          reload_nginx ;;
      esac
    done
  }

  # 1. registry entry, running:false
  registry_with_lock registry_upsert_validator "$name" custom "$port_base" "$party_hint" false \
    || { print_error "registry write failed"; return 1; }
  ADD_STEPS+=(registry)

  # 2. mint a fresh onboarding secret from the SV's DevNet prepare endpoint.
  # No rollback step needed — the token expires in ~1h and the SV has no
  # release endpoint; an unused one just ages out.
  print_step "Requesting onboarding secret from SV…"
  local onboarding_secret
  if ! onboarding_secret=$(_fetch_onboarding_secret); then
    _undo; print_error "could not fetch onboarding secret from SV"; return 1
  fi

  # 3. env file
  render_custom_env "$name" "$port_base" "$party_hint" "$onboarding_secret" \
    || { _undo; print_error "render env failed"; return 1; }
  ADD_STEPS+=(envfile)

  # 3. nginx conf
  render_nginx_conf "$name" \
    || { _undo; print_error "render nginx conf failed"; return 1; }
  ADD_STEPS+=(nginxconf)

  # 4. compose up
  mapfile -t argv < <(custom_compose_argv "$name")
  if ! "${argv[@]}" up -d; then
    _undo; print_error "docker compose up failed for validator-$name"; return 1
  fi
  ADD_STEPS+=(composeup)

  # 5. wait for readyz
  if ! _wait_for_custom_ready "$name" "$port_base"; then
    _undo; print_error "validator '$name' did not become ready within 90s"; return 1
  fi

  # 6. reload nginx (so wallet.<name>.localhost is served)
  reload_nginx
  ADD_STEPS+=(nginxreload)

  # 7. mark running:true
  registry_with_lock registry_set_running "$name" true

  print_ok "Validator '$name' is up."
  echo "  Wallet:    http://wallet.$name.localhost:5500"
  echo "  JSON API:  http://localhost:$((port_base + 75))"
  echo "  Party:     $party_hint"
}

validator_start() {
  local name="$1"
  [ -z "$name" ] && { print_error "usage: validator start <name>"; return 1; }
  if [ "$name" = "sv" ]; then
    print_error "sv is infrastructure; controlled by \`canton devrel start\`"; return 1
  fi
  if ! _infra_running; then
    print_error "infra not running; run \`canton devrel start\` first"; return 1
  fi
  local entry
  if ! entry=$(registry_get "$name"); then
    print_error "no such validator '$name'; run \`validator add $name\`"; return 1
  fi
  local type
  type=$(echo "$entry" | jq -r .type)
  if [ "$type" = "builtin" ]; then
    print_step "Starting built-in '$name' (toggles ${name^^}_PROFILE=on; brief infra restart)…"
    print_warning "SV will be unavailable ~10s; customs will reconnect."
    case "$name" in
      app-provider) export APP_PROVIDER_PROFILE=on ;;
      app-user)     export APP_USER_PROFILE=on ;;
    esac
    registry_with_lock registry_upsert_validator "$name" builtin "" "" true
    mapfile -t argv < <(infra_compose_argv)
    "${argv[@]}" up -d
  else
    local port_base
    port_base=$(echo "$entry" | jq -r .port_base)
    print_step "Starting custom '$name'…"
    mapfile -t argv < <(custom_compose_argv "$name")
    "${argv[@]}" up -d
    _wait_for_custom_ready "$name" "$port_base" || {
      print_error "'$name' did not become ready within 90s"; return 1
    }
    registry_with_lock registry_set_running "$name" true
  fi
  print_ok "'$name' is running."
}

validator_stop() {
  local name="$1"
  [ -z "$name" ] && { print_error "usage: validator stop <name>"; return 1; }
  if [ "$name" = "sv" ]; then
    print_error "sv is infrastructure; controlled by \`canton devrel stop\`"; return 1
  fi
  local entry
  if ! entry=$(registry_get "$name"); then
    print_error "no such validator '$name'"; return 1
  fi
  local type
  type=$(echo "$entry" | jq -r .type)
  if [ "$type" = "builtin" ]; then
    print_step "Stopping built-in '$name' (toggles ${name^^}_PROFILE=off; brief infra restart)…"
    print_warning "SV will be unavailable ~10s; customs will reconnect."
    case "$name" in
      app-provider) export APP_PROVIDER_PROFILE=off ;;
      app-user)     export APP_USER_PROFILE=off ;;
    esac
    registry_with_lock registry_set_running "$name" false
    mapfile -t argv < <(infra_compose_argv)
    "${argv[@]}" up -d
  else
    print_step "Stopping custom '$name' (volumes preserved)…"
    mapfile -t argv < <(custom_compose_argv "$name")
    "${argv[@]}" stop
    registry_with_lock registry_set_running "$name" false
  fi
  print_ok "'$name' stopped."
}

validator_rm() {
  local name="" force=0
  while [ $# -gt 0 ]; do
    case "$1" in
      --force) force=1; shift ;;
      *) name="$1"; shift ;;
    esac
  done
  [ -z "$name" ] && { print_error "usage: validator rm <name> [--force]"; return 1; }
  if [ "$name" = "sv" ]; then
    print_error "sv is infrastructure; controlled by \`canton devrel stop\`"; return 1
  fi
  local entry
  entry=$(registry_get "$name") || {
    if [ "$force" -eq 1 ] && [ -d "$CANTON_DEVREL_DIR/validators/$name" ]; then
      print_warning "no registry entry, but recipe dir exists — force-cleaning"
    else
      print_error "no such validator '$name'"; return 1
    fi
  }
  if [ -n "$entry" ]; then
    local type
    type=$(echo "$entry" | jq -r .type)
    if [ "$type" = "builtin" ]; then
      print_error "built-ins cannot be removed; use \`validator stop $name\`"; return 1
    fi
  fi

  print_step "Removing custom '$name' (data wiped)…"
  mapfile -t argv < <(custom_compose_argv "$name")
  "${argv[@]}" down -v 2>/dev/null || true
  rm -rf "$CANTON_DEVREL_DIR/validators/$name"
  remove_nginx_conf "$name"
  registry_with_lock registry_remove_validator "$name"
  reload_nginx
  print_ok "'$name' removed."
}
