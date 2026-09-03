#!/usr/bin/env bash
[[ -n "${_COMPOSE_SH_LOADED:-}" ]] && return; _COMPOSE_SH_LOADED=1

MODULES_DIR="${MODULES_DIR:-$HOME/.canton-builder/modules}"
LOCALNET_DIR="${LOCALNET_DIR:-$MODULES_DIR/localnet}"
VALIDATOR_BUNDLE_DIR="${VALIDATOR_BUNDLE_DIR:-$HOME/.canton-builder/bundle/splice-node/docker-compose/validator}"
OVERLAYS_DIR="${OVERLAYS_DIR:-$REPO_DIR/overlays}"

infra_compose_argv() {
  local force_all=0
  [ "${1:-}" = "--all" ] && force_all=1

  local want_keycloak=0 want_pqs=0
  if [ "$force_all" = "1" ]; then
    [ -f "$MODULES_DIR/keycloak/compose.yaml" ] && want_keycloak=1
    [ -f "$MODULES_DIR/pqs/compose.yaml" ]      && want_pqs=1
  else
    [ "${AUTH_MODE:-none}" = "oauth2" ] && [ -f "$MODULES_DIR/keycloak/compose.yaml" ] && want_keycloak=1
    [ "${PQS_ENABLED:-off}" = "on" ]    && [ -f "$MODULES_DIR/pqs/compose.yaml" ]      && want_pqs=1
  fi

  printf '%s\n' docker compose -p localnet
  printf '%s\n' --env-file "$LOCALNET_DIR/compose.env"
  printf '%s\n' --env-file "$LOCALNET_DIR/env/common.env"
  printf '%s\n' -f "$LOCALNET_DIR/compose.yaml"
  [ -f "$LOCALNET_DIR/resource-constraints.yaml" ] && \
    printf '%s\n' -f "$LOCALNET_DIR/resource-constraints.yaml"
  printf '%s\n' -f "$MODULES_DIR/splice-onboarding/compose.yaml"
  [ -f "$MODULES_DIR/splice-onboarding/resource-constraints.yaml" ] && \
    printf '%s\n' -f "$MODULES_DIR/splice-onboarding/resource-constraints.yaml"
  if [ "$want_keycloak" = "1" ]; then
    printf '%s\n' --env-file "$MODULES_DIR/keycloak/compose.env"
    printf '%s\n' -f "$MODULES_DIR/keycloak/compose.yaml"
    [ -f "$MODULES_DIR/keycloak/resource-constraints.yaml" ] && \
      printf '%s\n' -f "$MODULES_DIR/keycloak/resource-constraints.yaml"
  fi
  if [ "$want_pqs" = "1" ]; then
    printf '%s\n' --env-file "$MODULES_DIR/pqs/compose.env"
    printf '%s\n' -f "$MODULES_DIR/pqs/compose.yaml"
    [ -f "$MODULES_DIR/pqs/resource-constraints.yaml" ] && \
      printf '%s\n' -f "$MODULES_DIR/pqs/resource-constraints.yaml"
  fi
  printf '%s\n' --profile sv
  [ "${APP_PROVIDER_PROFILE:-on}" != "off" ] && printf '%s\n' --profile app-provider
  [ "${APP_USER_PROFILE:-on}" != "off" ]     && printf '%s\n' --profile app-user
  printf '%s\n' --profile swagger-ui
  if [ "$want_keycloak" = "1" ]; then
    printf '%s\n' --profile keycloak
  fi
  if [ "$want_pqs" = "1" ]; then
    printf '%s\n' --profile pqs-app-provider
    [ "${APP_USER_PROFILE:-on}" != "off" ] && printf '%s\n' --profile pqs-app-user
    [ "${PQS_SV_PROFILE:-off}" = "on" ]    && printf '%s\n' --profile pqs-sv
  fi
}
custom_compose_argv() {
  local name="$1"
  local envfile="$CANTON_DEVREL_DIR/validators/$name/env"
  cat <<EOF
docker
compose
-p
validator-$name
--env-file
$VALIDATOR_BUNDLE_DIR/.env
--env-file
$envfile
-f
$VALIDATOR_BUNDLE_DIR/compose.yaml
-f
$VALIDATOR_BUNDLE_DIR/compose-disable-auth.yaml
-f
$OVERLAYS_DIR/attach-localnet.overlay.yaml
EOF
}
infra_compose() {
  mapfile -t argv < <(infra_compose_argv "${1:-}")
  "${argv[@]}" "${@:2}"
}
custom_compose() {
  local name="$1"; shift
  mapfile -t argv < <(custom_compose_argv "$name")
  "${argv[@]}" "$@"
}