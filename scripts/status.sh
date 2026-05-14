#!/usr/bin/env bash
set -euo pipefail
DEVREL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$DEVREL_DIR/scripts/lib/common.sh"
source "$DEVREL_DIR/scripts/lib/registry.sh"
source "$DEVREL_DIR/scripts/lib/validator.sh"

print_header "Canton Builder Tool Network Status"

validator_list

echo ""
echo -e "  ${BOLD}Port Reference${NC}"
echo "  ────────────────────────────────────────────────"
printf "  %-38s %s\n" "SV Ledger API (gRPC)"          "localhost:4901"
printf "  %-38s %s\n" "SV JSON API"                   "localhost:4975"
printf "  %-38s %s\n" "SV Validator API"              "localhost:4903"
registry_read | jq -r '.validators[] | select(.type=="builtin")' | while read -r line; do
  : # rendered above by validator_list — skip; this section is just for the customs.
done
registry_read | jq -r '.validators[] | select(.type=="custom") | "\(.name) \(.port_base)"' \
  | while read -r name pb; do
    printf "  %-38s %s\n" "$name JSON API"           "localhost:$((pb + 75))"
    printf "  %-38s %s\n" "$name Validator API"      "localhost:$((pb + 3))"
    printf "  %-38s %s\n" "$name Ledger API"         "localhost:$((pb + 1))"
  done
printf "  %-38s %s\n" "PostgreSQL"                   "localhost:5432"
echo "  ────────────────────────────────────────────────"
echo ""
