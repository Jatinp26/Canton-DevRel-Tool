#!/usr/bin/env bats
# Auth helpers: self-signed HS256 minting, mode detection, and Keycloak client
# resolution from the fetched module env.
load ../test_helper

_b64url_decode() {
  local s="$1"
  s="${s//-/+}"; s="${s//_//}"
  case $(( ${#s} % 4 )) in 2) s="${s}==";; 3) s="${s}=";; esac
  printf '%s' "$s" | base64 -d 2>/dev/null
}

@test "auth_mode reflects AUTH_MODE" {
  run bash -c "source $REPO_DIR/scripts/lib/common.sh; AUTH_MODE=none auth_mode"
  [ "$output" = "self-signed" ]
  run bash -c "source $REPO_DIR/scripts/lib/common.sh; AUTH_MODE=oauth2 auth_mode"
  [ "$output" = "oauth2" ]
}

@test "mint_selfsigned_jwt emits a 3-part JWT" {
  run bash -c "source $REPO_DIR/scripts/lib/common.sh; mint_selfsigned_jwt ledger-api-user"
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | awk -F. '{print NF}')" -eq 3 ]
}

@test "mint_selfsigned_jwt payload carries the requested sub and default audience" {
  local jwt payload
  jwt=$(bash -c "source $REPO_DIR/scripts/lib/common.sh; mint_selfsigned_jwt ledger-api-user")
  payload=$(_b64url_decode "$(echo "$jwt" | cut -d. -f2)")
  echo "$payload" | grep -q '"sub":"ledger-api-user"'
  echo "$payload" | grep -q '"aud":"https://canton.network.global"'
}

@test "mint_selfsigned_jwt HS256 signature verifies with the shared secret" {
  local jwt si sig_got sig_exp
  jwt=$(bash -c "source $REPO_DIR/scripts/lib/common.sh; mint_selfsigned_jwt ledger-api-user")
  si="$(echo "$jwt" | cut -d. -f1,2)"
  sig_got="$(echo "$jwt" | cut -d. -f3)"
  sig_exp=$(printf '%s' "$si" | openssl dgst -sha256 -hmac "unsafe" -binary \
    | base64 | tr '+/' '-_' | tr -d '=' | tr -d '\n')
  [ "$sig_got" = "$sig_exp" ]
}

@test "_kc_client reads client id/secret from the fetched module env" {
  mkdir -p "$CANTON_DEVREL_DIR/modules/keycloak/env/app-provider/on"
  cat > "$CANTON_DEVREL_DIR/modules/keycloak/env/app-provider/on/oauth2.env" <<'EOF'
AUTH_APP_PROVIDER_VALIDATOR_CLIENT_ID=app-provider-validator
AUTH_APP_PROVIDER_VALIDATOR_CLIENT_SECRET=AL8648b9SfdTFImq7FV56Vd0KHifHBuC
EOF
  run bash -c "source $REPO_DIR/scripts/lib/common.sh; _kc_client app-provider"
  [ "$status" -eq 0 ]
  [ "$output" = "AppProvider app-provider-validator AL8648b9SfdTFImq7FV56Vd0KHifHBuC" ]
}

@test "ledger_token sv uses self-signed even when AUTH_MODE=oauth2" {
  # sv must not call keycloak; a stubbed curl that records calls should stay untouched.
  stub_cmd curl 0
  run bash -c "source $REPO_DIR/scripts/lib/common.sh; AUTH_MODE=oauth2 ledger_token sv"
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | awk -F. '{print NF}')" -eq 3 ]   # a JWT, not a curl result
  [ ! -f "$TMPHOME/cmd-calls" ]                            # curl was never invoked
}
