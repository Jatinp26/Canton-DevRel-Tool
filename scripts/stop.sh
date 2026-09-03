#!/usr/bin/env bash
set -euo pipefail
DEVREL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$DEVREL_DIR/scripts/lib/common.sh"
source "$DEVREL_DIR/scripts/lib/registry.sh"
source "$DEVREL_DIR/scripts/lib/compose.sh"

print_header "Canton Builder Tool Stopping LocalNet"
for n in $(registry_read | jq -r '.validators[] | select(.type=="custom") | .name'); do
  print_step "Stopping custom validator '$n'…"
  mapfile -t argv < <(custom_compose_argv "$n")
  "${argv[@]}" stop 2>/dev/null || true
done

print_step "Stopping localnet (data volumes preserved)…"
mapfile -t argv < <(infra_compose_argv --all)
"${argv[@]}" down

echo ""
print_ok "LocalNet stopped. Data volumes preserved."
echo "  Resume:    canton builder start"
echo "  Full wipe: canton builder reset"
echo ""