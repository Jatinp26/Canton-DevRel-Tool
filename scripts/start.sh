#!/usr/bin/env bash
# canton devrel start — boots Canton LocalNet using the official Splice bundle
set -euo pipefail

DEVREL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$DEVREL_DIR/scripts/lib/common.sh"
source "$DEVREL_DIR/scripts/lib/registry.sh"
source "$DEVREL_DIR/scripts/lib/resolve.sh"
source "$DEVREL_DIR/scripts/lib/compose.sh"

# ── Flag parsing: --validators/--only/--with/--without ────────────────────────
ABSOLUTE="" WITH="" WITHOUT=""
while [ $# -gt 0 ]; do
  case "$1" in
    --validators|--only) ABSOLUTE="$2"; shift 2 ;;
    --with)              WITH="$2"; shift 2 ;;
    --without)           WITHOUT="$2"; shift 2 ;;
    *) print_error "unknown flag: $1"; exit 1 ;;
  esac
done

RESOLVE_ARGS=()
[ -n "$ABSOLUTE" ] && RESOLVE_ARGS+=(--absolute "$ABSOLUTE")
[ -n "$WITH" ]     && RESOLVE_ARGS+=(--with "$WITH")
[ -n "$WITHOUT" ]  && RESOLVE_ARGS+=(--without "$WITHOUT")

RESOLVED=$(resolve_active_set "${RESOLVE_ARGS[@]}") || exit 1
eval "$(echo "$RESOLVED" | sed 's/^/export /')"

print_header "Canton DevRel — Starting LocalNet"
print_step "Active set: SV(on) APP_PROVIDER($APP_PROVIDER_PROFILE) APP_USER($APP_USER_PROFILE) CUSTOMS(${CUSTOMS:-none})"

# ── Preflight: Docker ─────────────────────────────────────────────────────────
if ! docker info &>/dev/null; then
  print_error "Docker is not running. Start Docker Desktop and try again."
  exit 1
fi
if ! docker compose version &>/dev/null; then
  print_error "Docker Compose v2 not found. Update Docker Desktop to get it."
  exit 1
fi

# ── Preflight: Memory ─────────────────────────────────────────────────────────
DOCKER_MEMORY_BYTES=$(docker info --format '{{.MemTotal}}' 2>/dev/null || echo 0)
DOCKER_MEMORY_GB=$(( DOCKER_MEMORY_BYTES / 1024 / 1024 / 1024 ))
if [ "$DOCKER_MEMORY_GB" -lt 7 ]; then
  print_warning "Docker has ~${DOCKER_MEMORY_GB}GB memory. LocalNet needs at least 8GB."
  print_warning "Go to Docker Desktop → Settings → Resources → Memory and increase it."
  echo ""
  read -rp "  Continue anyway? [y/N] " confirm
  confirm_lower="$(echo "$confirm" | tr '[:upper:]' '[:lower:]')"
  [ "$confirm_lower" = "y" ] || { echo "Aborted."; exit 1; }
fi

# ── Preflight: /etc/hosts ─────────────────────────────────────────────────────
MISSING_HOSTS=()
for domain in wallet.localhost scan.localhost sv.localhost; do
  grep -q "$domain" /etc/hosts 2>/dev/null || MISSING_HOSTS+=("$domain")
done

if [ ${#MISSING_HOSTS[@]} -gt 0 ]; then
  print_warning "Some *.localhost domains are not in /etc/hosts:"
  print_warning "  ${MISSING_HOSTS[*]}"
  echo ""
  echo "  Fix (requires sudo):"
  echo "    echo '127.0.0.1  wallet.localhost scan.localhost sv.localhost' | sudo tee -a /etc/hosts"
  echo ""
  read -rp "  Fix it automatically now? [y/N] " fix_hosts
  fix_hosts_lower="$(echo "$fix_hosts" | tr '[:upper:]' '[:lower:]')"
  if [ "$fix_hosts_lower" = "y" ]; then
    echo "127.0.0.1  wallet.localhost scan.localhost sv.localhost" | sudo tee -a /etc/hosts > /dev/null
    print_ok "Added to /etc/hosts."
  fi
fi

# ── Download bundle if not already present ────────────────────────────────────
BUNDLE_EXTRACT_DIR="${BUNDLE_DIR:-$HOME/.canton-devrel/bundle}"
LOCALNET_COMPOSE="$BUNDLE_EXTRACT_DIR/splice-node/docker-compose/localnet/compose.yaml"

if [ ! -f "$LOCALNET_COMPOSE" ]; then
  print_step "Downloading Splice LocalNet bundle v${IMAGE_TAG}..."
  echo "  This is a one-time download (~500MB). It will be cached for future runs."
  echo ""

  mkdir -p "$BUNDLE_EXTRACT_DIR"

  # Official release URL — digital-asset/decentralized-canton-sync
  TARBALL_URLS=(
    "https://github.com/digital-asset/decentralized-canton-sync/releases/download/v${IMAGE_TAG}/${IMAGE_TAG}_splice-node.tar.gz"
  )
  TARBALL_PATH="$BUNDLE_EXTRACT_DIR/${IMAGE_TAG}_splice-node.tar.gz"

  DOWNLOADED=0
  for TARBALL_URL in "${TARBALL_URLS[@]}"; do
    echo "  Trying: $TARBALL_URL"
    curl -fsSL --location --progress-bar "$TARBALL_URL" -o "$TARBALL_PATH" 2>/dev/null && {
      # Verify it is actually a gzip file, not an HTML error page
      if file "$TARBALL_PATH" 2>/dev/null | grep -q "gzip\|tar"; then
        DOWNLOADED=1
        break
      else
        print_warning "Downloaded file is not a valid tarball — trying next URL..."
        rm -f "$TARBALL_PATH"
      fi
    }
  done

  if [ $DOWNLOADED -eq 0 ]; then
    print_error "Could not download the Splice LocalNet bundle."
    echo ""
    echo "  Download it manually from:"
    echo "    https://github.com/digital-asset/decentralized-canton-sync/releases/tag/v${IMAGE_TAG}"
    echo ""
    echo "  Then place the file at:"
    echo "    $TARBALL_PATH"
    echo ""
    echo "  And re-run: canton devrel start"
    exit 1
  fi

  print_step "Extracting bundle..."
  tar -xzf "$TARBALL_PATH" -C "$BUNDLE_EXTRACT_DIR"
  rm -f "$TARBALL_PATH"
  print_ok "Bundle ready at $BUNDLE_EXTRACT_DIR"
else
  print_ok "Bundle already downloaded (v${IMAGE_TAG})"
fi

# ── Pull images ───────────────────────────────────────────────────────────────
print_step "Pulling Canton Network images (first run: ~3-5 min, then cached)..."
mapfile -t INFRA_ARGV < <(infra_compose_argv)
"${INFRA_ARGV[@]}" pull --quiet 2>/dev/null || {
  print_warning "Silent pull failed — retrying with output..."
  "${INFRA_ARGV[@]}" pull
}

# ── Start ─────────────────────────────────────────────────────────────────────
print_step "Starting LocalNet..."
"${INFRA_ARGV[@]}" up -d --remove-orphans

# ── Start custom validators in the active set ───────────────────────────────
if [ -n "${CUSTOMS:-}" ]; then
  IFS=',' read -ra CUSTOM_NAMES <<< "$CUSTOMS"
  for n in "${CUSTOM_NAMES[@]}"; do
    [ -z "$n" ] && continue
    print_step "Starting custom validator '$n'…"
    mapfile -t CUSTOM_ARGV < <(custom_compose_argv "$n")
    "${CUSTOM_ARGV[@]}" up -d
  done
fi

# ── Wait for validators ───────────────────────────────────────────────────────
print_step "Waiting for validators to be ready..."
echo "  This takes 2-4 minutes on first run. Hang tight."
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
echo ""

if [ $FAILED -eq 1 ]; then
  print_error "One or more validators failed to start."
  echo ""
  echo "  Check logs:   canton devrel logs"
  echo "  Reset:        canton devrel reset && canton devrel start"
  exit 1
fi

# ── Register the active set in the registry (lazy-create built-in entries) ──
registry_with_lock registry_upsert_validator app-provider builtin "" "" \
  "$( [ "$APP_PROVIDER_PROFILE" = "on" ] && echo true || echo false )"
registry_with_lock registry_upsert_validator app-user builtin "" "" \
  "$( [ "$APP_USER_PROFILE" = "on" ] && echo true || echo false )"

# ── Done ──────────────────────────────────────────────────────────────────────
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
echo "  Deploy your DAR:  canton devrel deploy ./your-project.dar"
echo "  Check status:     canton devrel status"
echo "  Stop:             canton devrel stop"
echo ""