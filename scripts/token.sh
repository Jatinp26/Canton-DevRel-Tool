#!/usr/bin/env bash
set -euo pipefail
DEVREL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$DEVREL_DIR/scripts/lib/common.sh"

TARGET="app-provider"
while [ $# -gt 0 ]; do
  case "$1" in
    --validator) TARGET="$2"; shift 2 ;;
    app-provider|app-user|sv) TARGET="$1"; shift ;;
    *) print_error "unknown arg: $1"; echo "  Usage: canton builder token [--validator app-provider|app-user|sv]" >&2; exit 1 ;;
  esac
done

case "$TARGET" in
  app-provider|app-user|sv) ;;
  *) print_error "unknown participant: $TARGET (expected app-provider, app-user, or sv)"; exit 1 ;;
esac

TOKEN="$(ledger_token "$TARGET")" || { print_error "Could not obtain a token for $TARGET."; exit 1; }
if [ -z "$TOKEN" ] || [ "$TOKEN" = "null" ]; then
  print_error "Empty token for $TARGET. In OAuth mode, is Keycloak up? (canton builder logs keycloak)"
  exit 1
fi
printf '%s\n' "$TOKEN"