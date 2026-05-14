#!/usr/bin/env bats
# Localnet's nginx is the only host-bound entry point for custom validator wallet
# UIs. Two non-obvious requirements:
#   - It must publish a host port that doesn't collide with macOS AirPlay
#     Receiver (which binds :5000 by default on Monterey+). We use :5500.
#   - It must include the rendered customs/*.conf files. The bundle's nginx.conf
#     only globs /etc/nginx/conf.d/*.conf (non-recursive), so we mount an
#     extended nginx.conf that also globs /etc/nginx/conf.d/customs/*.conf.
load ../test_helper

setup() {
  CUSTOMS_OVERLAY="$REPO_DIR/overlays/customs.overlay.yaml"
  NGINX_CONF="$REPO_DIR/overlays/nginx-conf/nginx.conf"
  NGINXCUSTOM_LIB="$REPO_DIR/scripts/lib/nginxcustom.sh"
}

@test "customs overlay publishes nginx on host :5500 (avoids macOS AirPlay :5000)" {
  grep -qE '"?\$\{HOST_BIND_IP[^}]*\}:5500:5500"?' "$CUSTOMS_OVERLAY"
}

@test "customs overlay does NOT publish nginx on the AirPlay-claimed :5000" {
  ! grep -qE ':5000:5000' "$CUSTOMS_OVERLAY"
}

@test "customs overlay mounts the patched nginx.conf via OVERLAYS_DIR" {
  grep -qE '\$\{OVERLAYS_DIR\}/nginx-conf/nginx\.conf:/etc/nginx/nginx\.conf' "$CUSTOMS_OVERLAY"
}

@test "customs overlay mounts the per-validator confs at /etc/nginx/conf.d/customs" {
  grep -qE '\$\{CANTON_DEVREL_DIR\}/nginx-customs:/etc/nginx/conf\.d/customs' "$CUSTOMS_OVERLAY"
}

@test "patched nginx.conf includes the customs subdirectory glob" {
  grep -qE '^\s*include\s+/etc/nginx/conf\.d/customs/\*\.conf\s*;' "$NGINX_CONF"
}

@test "patched nginx.conf preserves the bundle's primary include" {
  grep -qE '^\s*include\s+/etc/nginx/conf\.d/\*\.conf\s*;' "$NGINX_CONF"
}

@test "rendered per-validator conf listens on the new port" {
  source "$NGINXCUSTOM_LIB"
  local tmp; tmp="$(mktemp -d)"
  export CANTON_DEVREL_DIR="$tmp"
  render_nginx_conf acme
  local conf="$tmp/nginx-customs/acme.conf"
  [ -f "$conf" ]
  grep -qE '^\s*listen 5500;\s*$' "$conf"
  ! grep -qE '^\s*listen 5000;\s*$' "$conf"
  rm -rf "$tmp"
}

@test "customs overlay is wired into infra_compose_argv (so mount actually applies)" {
  source "$REPO_DIR/scripts/lib/common.sh"
  source "$REPO_DIR/scripts/lib/compose.sh"
  mapfile -t argv < <(infra_compose_argv)
  printf '%s\n' "${argv[@]}" | grep -q 'customs.overlay.yaml'
}
