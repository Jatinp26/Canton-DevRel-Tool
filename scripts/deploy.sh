#!/usr/bin/env bash
# canton devrel deploy <path/to/your.dar>
# Uploads a pre-built DAR to App Provider and App User participants
set -euo pipefail

DEVREL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$DEVREL_DIR/scripts/lib/common.sh"
source "$DEVREL_DIR/scripts/lib/registry.sh"

# ─── Args ─────────────────────────────────────────────────────────────────────

TARGET_VALIDATOR=""
while [ $# -gt 0 ]; do
  case "$1" in
    --validator) TARGET_VALIDATOR="$2"; shift 2 ;;
    *) break ;;
  esac
done

if [ $# -lt 1 ]; then
  echo ""
  print_error "Usage: canton devrel deploy [--validator <name>] <path/to/your.dar>"
  echo ""
  echo "  Examples:"
  echo "    canton devrel deploy ./my-app/.daml/dist/my-app-0.0.1.dar"
  echo "    canton devrel deploy --validator acme ./my-app/.daml/dist/my-app-0.0.1.dar"
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

print_header "Canton DevRel — Deploying DAR"
echo "  File: $DAR_FILENAME ($DAR_SIZE)"
echo ""

# ─── Check validators are up ──────────────────────────────────────────────────

print_step "Checking validators are reachable..."
for port in 3903 2903; do
  if ! curl -fs "http://localhost:${port}/api/validator/readyz" &>/dev/null; then
    print_error "Validator on port $port is not responding."
    echo "  Is LocalNet running? Try: canton devrel start"
    exit 1
  fi
done
print_ok "Validators reachable"

# ─── Generate JWT ─────────────────────────────────────────────────────────────
# The official Splice LocalNet uses HS256-signed JWTs.
# Secret: SPLICE_APP_UI_UNSAFE_SECRET (default: "unsafe")
# Audience: from AUTH_APP_PROVIDER_AUDIENCE env in the splice container

BUNDLE_COMMON_ENV="$LOCALNET_DIR/env/common.env"
SECRET="unsafe"
if [ -f "$BUNDLE_COMMON_ENV" ]; then
  PARSED=$(grep 'SPLICE_APP_UI_UNSAFE_SECRET' "$BUNDLE_COMMON_ENV" | \
    sed 's/.*:-\(.*\)}/\1/' | tr -d '"' | tr -d "'" | tr -d ' ')
  [ -n "$PARSED" ] && SECRET="$PARSED"
fi

# Base64url encode — no padding, URL-safe chars
b64url() {
  printf '%s' "$1" | base64 | tr '+/' '-_' | tr -d '=' | tr -d '\n'
}

make_jwt() {
  local user="$1"
  local audience="$2"
  local exp
  exp=$(( $(date +%s) + 86400 ))  # 24 hours

  local header
  header=$(b64url '{"alg":"HS256","typ":"JWT"}')

  local payload
  payload=$(b64url "{\"sub\":\"${user}\",\"aud\":\"${audience}\",\"exp\":${exp}}")

  local signing_input="${header}.${payload}"
  local sig
  sig=$(printf '%s' "$signing_input" | openssl dgst -sha256 -hmac "$SECRET" -binary | \
    base64 | tr '+/' '-_' | tr -d '=' | tr -d '\n')

  printf '%s' "${signing_input}.${sig}"
}

print_step "Generating JWT tokens (HS256, secret: ${SECRET})..."

PROVIDER_TOKEN=$(make_jwt "ledger-api-user" "https://canton.network.global")
USER_TOKEN=$(make_jwt "ledger-api-user" "https://canton.network.global")

print_ok "Tokens generated"

# ─── Upload DAR ───────────────────────────────────────────────────────────────

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

if [ -n "$TARGET_VALIDATOR" ]; then
  entry=$(registry_get "$TARGET_VALIDATOR") || {
    print_error "no such validator '$TARGET_VALIDATOR'"; exit 1
  }
  type=$(echo "$entry" | jq -r .type)
  if [ "$type" = "custom" ]; then
    pb=$(echo "$entry" | jq -r .port_base)
    target_port=$((pb + 75))
  else
    case "$TARGET_VALIDATOR" in
      app-provider) target_port=3975 ;;
      app-user)     target_port=2975 ;;
      sv)           target_port=4975 ;;
    esac
  fi
  upload_dar "$TARGET_VALIDATOR" "$target_port" "$PROVIDER_TOKEN"
else
  upload_dar "App Provider" 3975 "$PROVIDER_TOKEN"
  upload_dar "App User"     2975 "$USER_TOKEN"
fi

# ─── Package ID ───────────────────────────────────────────────────────────────

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
  print_warning "dpm not found — install dpm to get your package ID automatically."
fi

# ─── Done ─────────────────────────────────────────────────────────────────────

echo ""
echo -e "${GREEN}${BOLD}  ✓ DAR deployed successfully to LocalNet!${NC}"
echo ""
echo "  Your token for API calls (valid 24h):"
echo "    $PROVIDER_TOKEN"
echo ""
echo "  App Provider JSON API:  http://localhost:3975"
echo "  App User JSON API:      http://localhost:2975"
echo ""