#!/usr/bin/env bash
set -euo pipefail
DEVREL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$DEVREL_DIR/scripts/lib/common.sh"
source "$DEVREL_DIR/scripts/lib/registry.sh"

TARGET_VALIDATOR=""
while [ $# -gt 0 ]; do
  case "$1" in
    --validator) TARGET_VALIDATOR="$2"; shift 2 ;;
    *) break ;;
  esac
done

if [ $# -lt 1 ]; then
  echo ""
  print_error "Usage: canton builder deploy [--validator <name>] <path/to/your.dar>"
  echo ""
  echo "  Examples:"
  echo "    canton builder deploy ./my-app/.daml/dist/my-app-0.0.1.dar"
  echo "    canton builder deploy --validator acme ./my-app/.daml/dist/my-app-0.0.1.dar"
  echo ""
  exit 1
fi
DAR_PATH="$1"
if [ ! -f "$DAR_PATH" ]; then
  print_error "DAR file not found: $DAR_PATH"
  exit 1
fi

DAR_FILENAME=$(basename "$DAR_PATH")
DAR_SIZE=$(du -sh "$DAR_PATH" | cut -f1)
print_header "Deploying DAR"
echo "  File: $DAR_FILENAME ($DAR_SIZE)"
echo ""

declare -a TARGETS=()

_builtin_port_base_for() {
  case "$1" in
    sv)           echo 4900 ;;
    app-provider) echo 3900 ;;
    app-user)     echo 2900 ;;
    *)            return 1 ;;
  esac
}

if [ -n "$TARGET_VALIDATOR" ]; then
  if pb=$(_builtin_port_base_for "$TARGET_VALIDATOR"); then
    TARGETS+=("$TARGET_VALIDATOR:$pb")
  else
    entry=$(registry_get "$TARGET_VALIDATOR") || {
      print_error "no such validator '$TARGET_VALIDATOR'"; exit 1
    }
    pb=$(echo "$entry" | jq -r .port_base)
    TARGETS+=("$TARGET_VALIDATOR:$pb")
  fi
else
  while IFS= read -r entry; do
    name=$(echo "$entry" | jq -r .name)
    [ "$name" = "sv" ] && continue
    type=$(echo "$entry" | jq -r .type)
    if [ "$type" = "custom" ]; then
      pb=$(echo "$entry" | jq -r .port_base)
    else
      pb=$(_builtin_port_base_for "$name") || continue
    fi
    TARGETS+=("$name:$pb")
  done < <(registry_read | jq -c '.validators[] | select(.running == true)')

  if [ ${#TARGETS[@]} -eq 0 ]; then
    print_error "No running validators found in the registry."
    echo "  Try: canton builder start  (or: canton builder validator start <name>)"
    exit 1
  fi
fi

print_step "Checking validators are reachable..."
for target in "${TARGETS[@]}"; do
  name="${target%%:*}"; pb="${target##*:}"
  port=$((pb + 3))
  if ! curl -fs "http://localhost:${port}/api/validator/readyz" &>/dev/null; then
    print_error "Validator '$name' (validator API port $port) is not responding."
    echo "  Is LocalNet running? Try: canton builder start"
    exit 1
  fi
done
print_ok "Validators reachable"

print_step "Generating access token ($(auth_mode))..."
PROVIDER_TOKEN=$(ledger_token app-provider) || { print_error "Could not obtain an access token."; exit 1; }
if [ -z "$PROVIDER_TOKEN" ] || [ "$PROVIDER_TOKEN" = "null" ]; then
  print_error "Empty access token. In OAuth mode, is Keycloak up? Try: canton builder logs keycloak"
  exit 1
fi
print_ok "Token generated"

upload_dar() {
  local name="$1"
  local port="$2"
  local token="$3"
  echo ""
  print_step "Uploading to ${name} (port ${port})..."
  HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" -X POST \
    "http://localhost:${port}/v2/packages" \
    -H "Authorization: Bearer ${token}" \
    -H "Content-Type: application/octet-stream" \
    --data-binary "@${DAR_PATH}")

  case "$HTTP_CODE" in
    200|204)
      print_ok "Uploaded to ${name}" ;;
    409)
      print_ok "Already uploaded to ${name} (package exists — that's fine)" ;;
    401)
      print_error "Auth failed on ${name} (HTTP 401)"
      echo "  JWT may be malformed. Check openssl is available: openssl version"
      exit 1 ;;
    *)
      print_error "Upload failed on ${name} (HTTP ${HTTP_CODE})"
      exit 1 ;;
  esac
}

for target in "${TARGETS[@]}"; do
  name="${target%%:*}"; pb="${target##*:}"
  json_port=$((pb + 75))
  upload_dar "$name" "$json_port" "$PROVIDER_TOKEN"
done

echo ""
print_step "Resolving package ID..."

if command -v dpm &>/dev/null; then
  PACKAGE_ID=$(dpm damlc inspect-dar "$DAR_PATH" 2>/dev/null | \
    grep -v "dalf" | grep -v "^$" | \
    awk 'END{print}' | awk '{print $2}' | tr -d '"' || echo "")

  if [ -n "$PACKAGE_ID" ]; then
    echo ""
    print_ok "Package ID: $PACKAGE_ID"
    echo ""
    echo "  Template ID format for API calls:"
    echo "    ${PACKAGE_ID}:<ModuleName>:<TemplateName>"
    echo ""
    echo "  Example API call:"
    echo "    curl -X POST http://localhost:3975/v2/commands/submit-and-wait \\"
    echo "      -H \"Authorization: Bearer \$TOKEN\" \\"
    echo "      -H \"Content-Type: application/json\" \\"
    echo "      -d '{...}'"
  fi
else
  print_warning "dpm not found, install dpm to get your package ID automatically."
fi

echo ""
echo -e "${GREEN}${BOLD} DAR deployed successfully to LocalNet!${NC}"
echo ""
echo "  Your token for API calls (valid 24h):"
echo "    $PROVIDER_TOKEN"
echo ""
echo "  JSON APIs:"
for target in "${TARGETS[@]}"; do
  name="${target%%:*}"; pb="${target##*:}"
  printf "    %-16s http://localhost:%d\n" "$name" "$((pb + 75))"
done
echo ""