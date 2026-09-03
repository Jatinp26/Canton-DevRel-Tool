#!/usr/bin/env bash
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

print_header "Canton Builder Tool Reset"
print_warning "This will DELETE ledger data for:"
echo "  • All built-in validators (sv, app-provider, app-user)"
echo "  • All custom validators in the registry"
if [ "$PURGE" -eq 1 ]; then
  print_warning "AND wipe runtime state under $CANTON_DEVREL_DIR:"
  echo "    bundle/, validators/, nginx-customs/, validators.json, .registry.lock"
  echo "    (install files and .env are preserved)"
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
  print_step "Wiping runtime state in ${CANTON_DEVREL_DIR}…"
  rm -rf "$CANTON_DEVREL_DIR/bundle"
  rm -rf "$CANTON_DEVREL_DIR/validators"
  rm -rf "$CANTON_DEVREL_DIR/nginx-customs"
  rm -f  "$CANTON_DEVREL_DIR/validators.json"
  rm -f  "$CANTON_DEVREL_DIR/.registry.lock"
fi

echo ""
print_ok "Reset complete."
if [ "$PURGE" -eq 1 ]; then
  echo "  Runtime state wiped. Next 'canton builder start' re-downloads the bundle and starts fresh."
else
  echo "  Registry preserved. Next 'canton builder start' brings the same shape back with fresh ledgers."
fi
echo ""
