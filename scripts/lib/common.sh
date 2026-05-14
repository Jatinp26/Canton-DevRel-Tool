#!/usr/bin/env bash
# canton-devrel: shared helpers

# ── Colors ────────────────────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

print_header() {
  echo ""
  echo -e "${BOLD}${CYAN}══════════════════════════════════════════${NC}"
  echo -e "${BOLD}${CYAN}  $1${NC}"
  echo -e "${BOLD}${CYAN}══════════════════════════════════════════${NC}"
  echo ""
}
print_step()    { echo -e "${BLUE}▶  $1${NC}"; }
print_ok()      { echo -e "${GREEN}✓  $1${NC}"; }
print_warning() { echo -e "${YELLOW}⚠  $1${NC}"; }
print_error()   { echo -e "${RED}✗  $1${NC}"; }

# ── Paths ─────────────────────────────────────────────────────────────────────
# DEVREL_DIR must be set by the calling script before sourcing this file
DEVREL_DIR="${DEVREL_DIR:-$HOME/.canton-devrel}"

# Load our .env (IMAGE_TAG, BUNDLE_DIR)
if [ -f "$DEVREL_DIR/.env" ]; then
  set -a; source "$DEVREL_DIR/.env"; set +a
fi

# Where the official Splice bundle extracts to
BUNDLE_DIR="${BUNDLE_DIR:-$HOME/.canton-devrel/bundle}"
LOCALNET_DIR="$BUNDLE_DIR/splice-node/docker-compose/localnet"
VALIDATOR_BUNDLE_DIR="$BUNDLE_DIR/splice-node/docker-compose/validator"

# Repo paths (this file is at scripts/lib/common.sh).
REPO_DIR="${REPO_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
OVERLAYS_DIR="$REPO_DIR/overlays"

# Runtime state dir — the registry, recipes, nginx-customs all live here.
CANTON_DEVREL_DIR="${CANTON_DEVREL_DIR:-$HOME/.canton-devrel}"

# ── Official LocalNet compose command ─────────────────────────────────────────
# Exactly as documented at docs.sync.global/app_dev/testing/localnet.html
COMPOSE_CMD=(
  docker compose
  --env-file "$LOCALNET_DIR/compose.env"
  --env-file "$LOCALNET_DIR/env/common.env"
  -f "$LOCALNET_DIR/compose.yaml"
  -f "$LOCALNET_DIR/resource-constraints.yaml"
  --profile sv
  --profile app-provider
  --profile app-user
)

# ── Load Keycloak credentials from bundle env if available ────────────────────
# The official bundle ships its own Keycloak realm configs.
# We read client credentials from there if present, otherwise fall back
# to the known LocalNet defaults which match the quickstart.
BUNDLE_AUTH_ENV="$LOCALNET_DIR/env/auth.env"
if [ -f "$BUNDLE_AUTH_ENV" ]; then
  set -a; source "$BUNDLE_AUTH_ENV"; set +a
fi

# These match the LocalNet Keycloak defaults — override above if bundle differs
PROVIDER_CLIENT_ID="${APP_PROVIDER_CLIENT_ID:-app-provider-validator}"
PROVIDER_CLIENT_SECRET="${APP_PROVIDER_CLIENT_SECRET:-6m12QyyGl81d9nABWQXMycZdXho6ejEX}"
PROVIDER_REALM="${APP_PROVIDER_REALM:-AppProvider}"
PROVIDER_JSON_API="http://localhost:3975"

USER_CLIENT_ID="${APP_USER_CLIENT_ID:-app-user-validator}"
USER_CLIENT_SECRET="${APP_USER_CLIENT_SECRET:-6m12QyyGl81d9nABWQXMycZdXho6ejEX}"
USER_REALM="${APP_USER_REALM:-AppUser}"
USER_JSON_API="http://localhost:2975"

# ── Auth token helper ─────────────────────────────────────────────────────────
get_admin_token() {
  local realm="$1"
  local client_id="$2"
  local client_secret="$3"
  curl -fsS \
    "http://keycloak.localhost:8082/realms/${realm}/protocol/openid-connect/token" \
    -H 'Content-Type: application/x-www-form-urlencoded' \
    -d "client_id=${client_id}" \
    -d "client_secret=${client_secret}" \
    -d 'grant_type=client_credentials' \
    -d 'scope=openid' | jq -r .access_token
}