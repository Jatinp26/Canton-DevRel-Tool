#!/usr/bin/env bash
set -euo pipefail
DEVREL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$DEVREL_DIR/scripts/lib/common.sh"
source "$DEVREL_DIR/scripts/lib/compose.sh"

VALIDATOR=""
while [ $# -gt 0 ]; do
  case "$1" in
    --validator) VALIDATOR="$2"; shift 2 ;;
    *) break ;;
  esac
done

SERVICE="${1:-}"
echo ""
if [ -n "$VALIDATOR" ]; then
  print_step "Tailing logs for validator-$VALIDATOR ${SERVICE:+(service: $SERVICE)}"
  mapfile -t argv < <(custom_compose_argv "$VALIDATOR")
  exec "${argv[@]}" logs -f --tail=50 ${SERVICE:+"$SERVICE"}
else
  if [ -n "$SERVICE" ]; then
    print_step "Tailing logs for: $SERVICE (Ctrl+C to stop)"
  else
    print_step "Tailing all infra logs (Ctrl+C to stop)"
    echo "  Tip: --validator <name>  to tail a custom validator's logs."
  fi
  mapfile -t argv < <(infra_compose_argv --all)
  exec "${argv[@]}" logs -f --tail=50 ${SERVICE:+"$SERVICE"}
fi