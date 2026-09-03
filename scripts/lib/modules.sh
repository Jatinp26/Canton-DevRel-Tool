#!/usr/bin/env bash
[[ -n "${_MODULES_SH_LOADED:-}" ]] && return; _MODULES_SH_LOADED=1

KEPT_MODULES=(localnet splice-onboarding keycloak pqs)
CNQS_REPO="digital-asset/cn-quickstart"
ensure_modules() {
  local ref="${CNQS_REF:?CNQS_REF is not set}"
  local marker="$MODULES_DIR/.ref"
  if [ -f "$marker" ] && [ "$(cat "$marker" 2>/dev/null)" = "$ref" ] \
     && [ -f "$LOCALNET_DIR/compose.yaml" ]; then
    print_ok "LocalNet modules ready (cn-quickstart @ ${ref:0:12})"
    return 0
  fi
  print_step "Fetching LocalNet modules (cn-quickstart @ ${ref:0:12})..."
  mkdir -p "$MODULES_DIR"

  local tmp tarball url
  tmp="$(mktemp -d)"
  tarball="$tmp/cnqs.tar.gz"
  url="https://codeload.github.com/${CNQS_REPO}/tar.gz/${ref}"

  if ! curl -fsSL "$url" -o "$tarball"; then
    rm -rf "$tmp"
    print_error "Could not download cn-quickstart modules from:"
    echo "    $url"
    echo "  Check the CNQS_REF pin in your .env, and your network settings."
    return 1
  fi

  if ! tar -xzf "$tarball" -C "$tmp"; then
    rm -rf "$tmp"
    print_error "Downloaded archive could not be extracted."
    return 1
  fi

  local src
  src="$(ls -d "$tmp"/*/quickstart/docker/modules 2>/dev/null | head -1)"
  if [ -z "$src" ] || [ ! -d "$src" ]; then
    rm -rf "$tmp"
    print_error "Could not locate docker/modules in the cn-quickstart archive."
    return 1
  fi

  local m
  for m in "${KEPT_MODULES[@]}"; do
    if [ -d "$src/$m" ]; then
      rm -rf "${MODULES_DIR:?}/$m"
      cp -R "$src/$m" "$MODULES_DIR/$m"
    else
      print_warning "module '$m' not present in this cn-quickstart ref — skipping."
    fi
  done

  echo "$ref" > "$marker"
  rm -rf "$tmp"
  print_ok "LocalNet modules ready at $MODULES_DIR"
}

ensure_splice_bundle() {
  local extract_dir="${BUNDLE_DIR:-$CANTON_DEVREL_DIR/bundle}"
  local validator_compose="$extract_dir/splice-node/docker-compose/validator/compose.yaml"
  [ -f "$validator_compose" ] && return 0
  print_step "Downloading Splice bundle for custom validators (v${IMAGE_TAG})..."
  mkdir -p "$extract_dir"
  local url tarball
  url="https://github.com/digital-asset/decentralized-canton-sync/releases/download/v${IMAGE_TAG}/${IMAGE_TAG}_splice-node.tar.gz"
  tarball="$extract_dir/${IMAGE_TAG}_splice-node.tar.gz"
  if ! curl -fsSL --location "$url" -o "$tarball"; then
    print_error "Could not download the Splice bundle from:"
    echo "    $url"
    return 1
  fi
  tar -xzf "$tarball" -C "$extract_dir"
  rm -f "$tarball"
  print_ok "Splice bundle ready at $extract_dir"
}