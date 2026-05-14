#!/usr/bin/env bash
# Build docker compose argv arrays for the localnet (infra) and per-custom projects.
[[ -n "${_COMPOSE_SH_LOADED:-}" ]] && return; _COMPOSE_SH_LOADED=1

# Paths set by callers (common.sh) — but provide defaults so the lib is usable standalone.
LOCALNET_DIR="${LOCALNET_DIR:-$HOME/.canton-devrel/bundle/splice-node/docker-compose/localnet}"
VALIDATOR_BUNDLE_DIR="${VALIDATOR_BUNDLE_DIR:-$HOME/.canton-devrel/bundle/splice-node/docker-compose/validator}"
OVERLAYS_DIR="${OVERLAYS_DIR:-$REPO_DIR/overlays}"

# Print one argv element per line: full docker compose argv for the localnet project.
# Profile flags are appended based on *_PROFILE env vars. Unset == "on" so that
# broad-coverage callers (stop, logs, reset) target every profile by default,
# while `start` can opt specific built-ins out by setting them to "off".
infra_compose_argv() {
  cat <<EOF
docker
compose
-p
localnet
--env-file
$LOCALNET_DIR/compose.env
--env-file
$LOCALNET_DIR/env/common.env
-f
$LOCALNET_DIR/compose.yaml
-f
$LOCALNET_DIR/resource-constraints.yaml
-f
$OVERLAYS_DIR/customs.overlay.yaml
-f
$OVERLAYS_DIR/party-hint.overlay.yaml
-f
$OVERLAYS_DIR/sv-scan-url.overlay.yaml
--profile
sv
EOF
  if [ "${APP_PROVIDER_PROFILE:-on}" != "off" ]; then
    printf '%s\n' "--profile" "app-provider"
  fi
  if [ "${APP_USER_PROFILE:-on}" != "off" ]; then
    printf '%s\n' "--profile" "app-user"
  fi
}

# Print one argv element per line: full docker compose argv for the per-custom project.
# Bundle .env is included first so it supplies defaults (NGINX_VERSION, SPLICE_DB_*, etc.)
# that docker compose would otherwise auto-load — auto-loading is disabled as soon as any
# --env-file is passed, so we must list it explicitly. The rendered env file is listed last
# so its values override the bundle defaults.
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

# Convenience: read the lines into an array and execute.
infra_compose() {
  mapfile -t argv < <(infra_compose_argv)
  "${argv[@]}" "$@"
}

custom_compose() {
  local name="$1"; shift
  mapfile -t argv < <(custom_compose_argv "$name")
  "${argv[@]}" "$@"
}
