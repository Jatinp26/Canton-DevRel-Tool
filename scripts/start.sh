#!/usr/bin/env bash

set -euo pipefail
DEVREL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$DEVREL_DIR/scripts/lib/common.sh"
source "$DEVREL_DIR/scripts/lib/registry.sh"
source "$DEVREL_DIR/scripts/lib/resolve.sh"
source "$DEVREL_DIR/scripts/lib/compose.sh"
source "$DEVREL_DIR/scripts/lib/modules.sh"

ABSOLUTE="" WITH="" WITHOUT="" WANT_AUTH=0 WANT_PQS=0
while [ $# -gt 0 ]; do
  case "$1" in
    --validators|--only) ABSOLUTE="$2"; shift 2 ;;
    --with)              WITH="$2"; shift 2 ;;
    --without)           WITHOUT="$2"; shift 2 ;;
    --auth)              WANT_AUTH=1; shift ;;
    --pqs)               WANT_PQS=1; shift ;;
    *) print_error "unknown flag: $1"; exit 1 ;;
  esac
done

RESOLVE_ARGS=()
[ -n "$ABSOLUTE" ] && RESOLVE_ARGS+=(--absolute "$ABSOLUTE")
[ -n "$WITH" ]     && RESOLVE_ARGS+=(--with "$WITH")
[ -n "$WITHOUT" ]  && RESOLVE_ARGS+=(--without "$WITHOUT")

RESOLVED=$(resolve_active_set "${RESOLVE_ARGS[@]}") || exit 1
eval "$(echo "$RESOLVED" | sed 's/^/export /')"

export AUTH_MODE=$( [ "$WANT_AUTH" = "1" ] && echo oauth2 || echo none )
export PQS_ENABLED=$( [ "$WANT_PQS" = "1" ] && echo on || echo off )
{
  echo "AUTH_MODE=$AUTH_MODE"
  echo "PQS_ENABLED=$PQS_ENABLED"
} > "$CANTON_DEVREL_DIR/.mode"

print_header "Canton Builder Tool Starting LocalNet"
print_step "Active set: SV(on) APP_PROVIDER($APP_PROVIDER_PROFILE) APP_USER($APP_USER_PROFILE) CUSTOMS(${CUSTOMS:-none})"
print_step "Auth: $(auth_mode)   PQS: ${PQS_ENABLED}"
if [ "$WANT_AUTH" = "1" ] && [ "$APP_USER_PROFILE" = "off" ]; then
  print_warning "Auth is on but app-user is off — add '--with app-user' to test user-side OAuth flows."
fi

if ! docker info &>/dev/null; then
  print_error "Docker is not running. Start Docker Desktop and try again."
  exit 1
fi
if ! docker compose version &>/dev/null; then
  print_error "Docker Compose v2 not found. Update Docker Desktop to get it."
  exit 1
fi

DOCKER_MEMORY_BYTES=$(docker info --format '{{.MemTotal}}' 2>/dev/null || echo 0)
DOCKER_MEMORY_GB=$(( DOCKER_MEMORY_BYTES / 1024 / 1024 / 1024 ))
if [ "$DOCKER_MEMORY_GB" -lt 7 ]; then
  print_warning "Docker has ~${DOCKER_MEMORY_GB}GB memory. LocalNet needs at least 8GB."
  print_warning "Go to Docker Desktop Settings and Under Resources, Check Memory and increase it."
  echo ""
  read -rp "  Continue anyway? [y/N] " confirm
  confirm_lower="$(echo "$confirm" | tr '[:upper:]' '[:lower:]')"
  [ "$confirm_lower" = "y" ] || { echo "Aborted."; exit 1; }
fi

REQUIRED_HOSTS=(wallet.localhost scan.localhost sv.localhost)
[ "$WANT_AUTH" = "1" ] && REQUIRED_HOSTS+=(keycloak.localhost)
MISSING_HOSTS=()
for domain in "${REQUIRED_HOSTS[@]}"; do
  grep -q "$domain" /etc/hosts 2>/dev/null || MISSING_HOSTS+=("$domain")
done

if [ ${#MISSING_HOSTS[@]} -gt 0 ]; then
  print_warning "Some *.localhost domains are not in /etc/hosts:"
  print_warning "  ${MISSING_HOSTS[*]}"
  echo ""
  echo "  Fix (requires sudo):"
  echo "    echo '127.0.0.1  ${MISSING_HOSTS[*]}' | sudo tee -a /etc/hosts"
  echo ""
  read -rp "  Fix it automatically now? [y/N] " fix_hosts
  fix_hosts_lower="$(echo "$fix_hosts" | tr '[:upper:]' '[:lower:]')"
  if [ "$fix_hosts_lower" = "y" ]; then
    echo "127.0.0.1  ${MISSING_HOSTS[*]}" | sudo tee -a /etc/hosts > /dev/null
    print_ok "Added to /etc/hosts."
    if grep -qi "microsoft" /proc/version 2>/dev/null; then
      print_warning "WSL detected: /etc/hosts may reset on reboot. If domains stop resolving, re run canton builder start."
    fi
  fi
fi

ensure_modules || exit 1
if [ -n "${CUSTOMS:-}" ]; then
  ensure_splice_bundle || exit 1
fi

print_step "Pulling Canton Network images (first run: ~3-5 min, then cached)..."
mapfile -t INFRA_ARGV < <(infra_compose_argv)
"${INFRA_ARGV[@]}" pull --quiet 2>/dev/null || {
  print_warning "Silent pull failed — retrying with output..."
  "${INFRA_ARGV[@]}" pull
}
print_step "Starting LocalNet..."
"${INFRA_ARGV[@]}" up -d --remove-orphans

if [ -n "${CUSTOMS:-}" ]; then
  IFS=',' read -ra CUSTOM_NAMES <<< "$CUSTOMS"
  for n in "${CUSTOM_NAMES[@]}"; do
    [ -z "$n" ] && continue
    print_step "Starting custom validator '$n'…"
    mapfile -t CUSTOM_ARGV < <(custom_compose_argv "$n")
    "${CUSTOM_ARGV[@]}" up -d
  done
fi

print_step "Waiting for validators to be ready..."
echo "  This takes ~5 minutes on first run. Hang tight."
echo ""

wait_for_validator() {
  local name="$1"
  local port="$2"
  local max_attempts=60
  local attempt=0
  printf "  %-20s" "$name"
  while [ $attempt -lt $max_attempts ]; do
    if curl -fs "http://localhost:${port}/api/validator/readyz" &>/dev/null; then
      print_ok "ready"
      return 0
    fi
    printf "."
    sleep 5
    (( attempt++ ))
  done
  echo ""
  print_error "timed out after $((max_attempts * 5))s"
  return 1
}

FAILED=0
wait_for_validator "Super Validator" 4903 || FAILED=1
if [ "$APP_PROVIDER_PROFILE" = "on" ]; then
  wait_for_validator "App Provider" 3903 || FAILED=1
fi
if [ "$APP_USER_PROFILE" = "on" ]; then
  wait_for_validator "App User" 2903 || FAILED=1
fi
if [ -n "${CUSTOMS:-}" ]; then
  IFS=',' read -ra CUSTOM_NAMES <<< "$CUSTOMS"
  for n in "${CUSTOM_NAMES[@]}"; do
    [ -z "$n" ] && continue
    entry=$(registry_get "$n") || continue
    pb=$(echo "$entry" | jq -r .port_base)
    wait_for_validator "$n" $((pb + 3)) || FAILED=1
  done
fi

if [ "$WANT_AUTH" = "1" ]; then
  printf "  %-20s" "Keycloak"
  kc_ok=0
  for _ in $(seq 1 30); do
    if curl -fs "http://keycloak.localhost:8082/realms/AppProvider/.well-known/openid-configuration" &>/dev/null; then
      print_ok "ready"; kc_ok=1; break
    fi
    printf "."; sleep 5
  done
  [ "$kc_ok" = "1" ] || { echo ""; print_warning "Keycloak not ready yet — it may need another minute."; }
fi
echo ""

if [ $FAILED -eq 1 ]; then
  print_error "One or more validators failed to start."
  echo ""
  echo "  Check logs: canton builder logs"
  echo "  Reset: canton builder reset && canton builder start"
  exit 1
fi

registry_with_lock registry_upsert_validator app-provider builtin "" "" \
  "$( [ "$APP_PROVIDER_PROFILE" = "on" ] && echo true || echo false )"
registry_with_lock registry_upsert_validator app-user builtin "" "" \
  "$( [ "$APP_USER_PROFILE" = "on" ] && echo true || echo false )"

print_header "LocalNet is up! 🎉"
echo ""
echo "  Wallet UIs:"
[ "$APP_USER_PROFILE" = "on" ]     && echo "    App User     →  http://wallet.localhost:2000  (login: app-user)"
[ "$APP_PROVIDER_PROFILE" = "on" ] && echo "    App Provider →  http://wallet.localhost:3000  (login: app-provider)"
echo "    Scan         →  http://scan.localhost:4000"
echo "    SV UI        →  http://sv.localhost:4000"
echo ""
echo "  JSON Ledger API:"
[ "$APP_PROVIDER_PROFILE" = "on" ] && echo "    App Provider →  http://localhost:3975"
[ "$APP_USER_PROFILE" = "on" ]     && echo "    App User     →  http://localhost:2975"
echo ""
if [ "$WANT_AUTH" = "1" ]; then
  echo "  Auth: OAuth2 (Keycloak)"
  echo "    Token endpoint →  http://keycloak.localhost:8082/realms/{AppProvider,AppUser}/protocol/openid-connect/token"
  echo "    Admin console  →  http://keycloak.localhost:8082  (admin / admin)"
  echo "    Realms: AppProvider, AppUser   Grant: client_credentials"
else
  echo "  Auth: self-signed HS256 (secret: $(auth_selfsigned_secret), audience: ${AUTH_AUDIENCE})"
fi
echo ""
echo "  Credentials & parties:  canton builder env"
echo "  Get a token:            canton builder token [--validator app-provider|app-user|sv]"
echo "  Deploy your DAR:        canton builder deploy ./your-project.dar"
echo "  Check status:           canton builder status"
echo "  Stop:                   canton builder stop"
echo ""