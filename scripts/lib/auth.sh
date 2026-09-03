#!/usr/bin/env bash
[[ -n "${_AUTH_SH_LOADED:-}" ]] && return; _AUTH_SH_LOADED=1

AUTH_AUDIENCE="${AUTH_AUDIENCE:-https://canton.network.global}"
auth_selfsigned_secret() {
  local common_env="${LOCALNET_DIR:-}/env/common.env"
  local secret="${SPLICE_APP_UI_UNSAFE_SECRET:-unsafe}"
  if [ -f "$common_env" ]; then
    local parsed
    parsed=$(grep -E '^SPLICE_APP_UI_UNSAFE_SECRET' "$common_env" 2>/dev/null \
      | sed 's/.*:-\(.*\)}/\1/' | tr -d '"' | tr -d "'" | tr -d ' ')
    [ -n "$parsed" ] && secret="$parsed"
  fi
  printf '%s' "$secret"
}
auth_mode() {
  [ "${AUTH_MODE:-none}" = "oauth2" ] && echo "oauth2" || echo "self-signed"
}

_b64url() { printf '%s' "$1" | base64 | tr '+/' '-_' | tr -d '=' | tr -d '\n'; }
mint_selfsigned_jwt() {
  local user="$1"
  local audience="${2:-$AUTH_AUDIENCE}"
  local secret exp header payload signing_input sig
  secret="$(auth_selfsigned_secret)"
  exp=$(( $(date +%s) + 86400 ))
  header=$(_b64url '{"alg":"HS256","typ":"JWT"}')
  payload=$(_b64url "{\"sub\":\"${user}\",\"aud\":\"${audience}\",\"exp\":${exp}}")
  signing_input="${header}.${payload}"
  sig=$(printf '%s' "$signing_input" | openssl dgst -sha256 -hmac "$secret" -binary \
    | base64 | tr '+/' '-_' | tr -d '=' | tr -d '\n')
  printf '%s' "${signing_input}.${sig}"
}

keycloak_token() {
  local realm="$1" cid="$2" csec="$3"
  curl -fsS \
    "http://keycloak.localhost:8082/realms/${realm}/protocol/openid-connect/token" \
    -H 'Content-Type: application/x-www-form-urlencoded' \
    -d "client_id=${cid}" \
    -d "client_secret=${csec}" \
    -d 'grant_type=client_credentials' \
    -d 'scope=openid' | jq -r .access_token
}

_kc_client() {
  local participant="$1" realm var_prefix envfile cid csec
  case "$participant" in
    app-provider) realm="AppProvider"; var_prefix="AUTH_APP_PROVIDER_VALIDATOR"
                  envfile="${MODULES_DIR}/keycloak/env/app-provider/on/oauth2.env" ;;
    app-user)     realm="AppUser";     var_prefix="AUTH_APP_USER_VALIDATOR"
                  envfile="${MODULES_DIR}/keycloak/env/app-user/on/oauth2.env" ;;
    *) return 1 ;;
  esac
  [ -f "$envfile" ] || return 1
  cid=$(grep -E "^${var_prefix}_CLIENT_ID=" "$envfile" | head -1 | cut -d= -f2- | awk '{print $1}')
  csec=$(grep -E "^${var_prefix}_CLIENT_SECRET=" "$envfile" | head -1 | cut -d= -f2- | awk '{print $1}')
  [ -n "$cid" ] && [ -n "$csec" ] || return 1
  printf '%s %s %s' "$realm" "$cid" "$csec"
}

ledger_token() {
  local participant="${1:-app-provider}"
  if [ "$participant" = "sv" ] || [ "$(auth_mode)" = "self-signed" ]; then
    mint_selfsigned_jwt "ledger-api-user"
    return
  fi
  local triple realm cid csec
  triple="$(_kc_client "$participant")" || {
    echo "could not resolve Keycloak client for '$participant' (is the keycloak module fetched?)" >&2
    return 1
  }
  read -r realm cid csec <<< "$triple"
  keycloak_token "$realm" "$cid" "$csec"
}