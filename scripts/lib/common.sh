#!/usr/bin/env bash
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

CANTON_DEVREL_DIR="${CANTON_DEVREL_DIR:-${CANTON_BUILDER_DIR:-$HOME/.canton-builder}}"
DEVREL_DIR="$CANTON_DEVREL_DIR"
if [ -f "$CANTON_DEVREL_DIR/.env" ]; then
  set -a; source "$CANTON_DEVREL_DIR/.env"; set +a
fi
SPLICE_VERSION="${SPLICE_VERSION:-0.6.11}"
export IMAGE_TAG="${IMAGE_TAG:-$SPLICE_VERSION}"
export CNQS_REF="${CNQS_REF:-93f97b34eb47709e6484eb2e3dc6f722d328063b}"
export MODULES_DIR="${MODULES_DIR:-$CANTON_DEVREL_DIR/modules}"
export LOCALNET_DIR="$MODULES_DIR/localnet"
export LOCALNET_ENV_DIR="$LOCALNET_DIR/env"
export PARTY_HINT="${PARTY_HINT:-builder-localnet-1}"
export SPLICE_APP_UI_UNSAFE_SECRET="${SPLICE_APP_UI_UNSAFE_SECRET:-unsafe}"
BUNDLE_DIR="${BUNDLE_DIR:-$CANTON_DEVREL_DIR/bundle}"
VALIDATOR_BUNDLE_DIR="$BUNDLE_DIR/splice-node/docker-compose/validator"

REPO_DIR="${REPO_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
export OVERLAYS_DIR="$REPO_DIR/overlays"
MODE_FILE="$CANTON_DEVREL_DIR/.mode"
if [ -f "$MODE_FILE" ]; then
  set -a; source "$MODE_FILE"; set +a
fi
export AUTH_MODE="${AUTH_MODE:-none}"
export PQS_ENABLED="${PQS_ENABLED:-off}"

source "$REPO_DIR/scripts/lib/auth.sh"