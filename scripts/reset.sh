#!/usr/bin/env bash
# canton devrel reset [--purge] — wipe ledger data (and optionally state dir).
set -euo pipefail

DEVREL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$DEVREL_DIR/scripts/lib/common.sh"
source "$DEVREL_DIR/scripts/lib/registry.sh"
source "$DEVREL_DIR/scripts/lib/compose.sh"

PURGE=0
for arg in "$@"; do
  case "$arg" in
    --purge) PURGE=1 ;;
    *) print_error "unknown flag: $arg"; exit 1 ;;
  esac
done

print_header "Canton DevRel — Reset"
print_warning "This will DELETE ledger data for:"
echo "  • All built-in validators (sv, app-provider, app-user)"
echo "  • All custom validators in the registry"
if [ "$PURGE" -eq 1 ]; then
  print_warning "AND wipe $CANTON_DEVREL_DIR (recipes, registry, env files, nginx-customs)."
fi
echo ""
read -rp "  Are you sure? Type 'yes' to confirm: " confirm
[ "$confirm" = "yes" ] || { echo "  Aborted."; exit 0; }

echo ""
print_step "Tearing down custom validator projects…"
for n in $(registry_read | jq -r '.validators[] | select(.type=="custom") | .name'); do
  print_step "  validator-$n"
  mapfile -t argv < <(custom_compose_argv "$n")
  "${argv[@]}" down -v 2>/dev/null || true
done

print_step "Tearing down localnet…"
mapfile -t argv < <(infra_compose_argv)
"${argv[@]}" down -v 2>/dev/null || true

if [ "$PURGE" -eq 1 ]; then
  print_step "Wiping $CANTON_DEVREL_DIR…"
  rm -rf "$CANTON_DEVREL_DIR"
fi

echo ""
print_ok "Reset complete."
if [ "$PURGE" -eq 1 ]; then
  echo "  State dir gone. Next 'canton devrel start' starts from scratch."
else
  echo "  Recipes preserved. Next 'canton devrel start' brings the same shape back with fresh ledgers."
fi
echo ""
