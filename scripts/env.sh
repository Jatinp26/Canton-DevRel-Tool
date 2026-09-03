#!/usr/bin/env bash
set -euo pipefail
DEVREL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$DEVREL_DIR/scripts/lib/common.sh"
MODE="$(auth_mode)"
print_header "Canton Builder Tool — Environment"
echo "  Auth model:   $MODE"
if [ "$MODE" = "oauth2" ]; then
  echo "  Keycloak:     http://keycloak.localhost:8082  (admin console: admin / admin)"
  echo "  Grant:        client_credentials"
else
  echo "  Secret:       $(auth_selfsigned_secret)   (HS256, self-signed)"
fi
echo "  Audience:     ${AUTH_AUDIENCE}"
echo "  PQS:          ${PQS_ENABLED}"
echo ""

PARTICIPANTS=(
  "app-provider 3975 3901 3903 AppProvider"
  "app-user     2975 2901 2903 AppUser"
  "sv           4975 4901 4903 -"
)

fetch_parties() {
  local json_port="$1" token="$2"
  local body
  body=$(curl -fsS --max-time 5 \
    -H "Authorization: Bearer ${token}" \
    "http://localhost:${json_port}/v2/parties" 2>/dev/null) || { echo ""; return 1; }
  echo "$body" | jq -r '(.partyDetails // .parties // .)[]?.party // empty' 2>/dev/null | paste -sd, - 2>/dev/null
}

for row in "${PARTICIPANTS[@]}"; do
  read -r name json ledger validator realm <<< "$row"
  reachable=0
  curl -fs --max-time 3 "http://localhost:${validator}/api/validator/readyz" &>/dev/null && reachable=1

  echo -e "  ${BOLD}${name}${NC}"
  echo "    JSON Ledger API   →  http://localhost:${json}"
  echo "    Ledger API (gRPC) →  localhost:${ledger}"
  echo "    Validator API     →  http://localhost:${validator}"
  echo "    ledger-api user   →  ledger-api-user"

  if [ "$MODE" = "oauth2" ] && [ "$name" != "sv" ]; then
    if triple="$(_kc_client "$name" 2>/dev/null)"; then
      read -r kc_realm kc_id kc_secret <<< "$triple"
      echo "    Realm             →  ${kc_realm}"
      echo "    Client ID         →  ${kc_id}"
      echo "    Client secret     →  ${kc_secret}"
      echo "    Token URL         →  http://keycloak.localhost:8082/realms/${kc_realm}/protocol/openid-connect/token"
    fi
  fi

  if [ "$reachable" = "1" ]; then
    token="$(ledger_token "$name" 2>/dev/null || true)"
    if [ -n "$token" ] && [ "$token" != "null" ]; then
      parties="$(fetch_parties "$json" "$token" || true)"
      [ -n "$parties" ] && echo "    Parties           →  ${parties}"
      echo "    Token (24h)       →  ${token}"
    else
      echo "    Token             →  (could not mint — see: canton builder logs)"
    fi
  else
    echo "    Status            →  not reachable (is it in the active set / is LocalNet up?)"
  fi
  echo ""
done

echo "  Tip: export a token for quick calls:"
echo "    export TOKEN=\$(canton builder token --validator app-provider)"
echo "    curl -H \"Authorization: Bearer \$TOKEN\" http://localhost:3975/v2/parties"
echo ""