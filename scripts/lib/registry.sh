#!/usr/bin/env bash
# Atomic JSON registry under ~/.canton-devrel/validators.json.
[[ -n "${_REGISTRY_SH_LOADED:-}" ]] && return; _REGISTRY_SH_LOADED=1

CANTON_DEVREL_DIR="${CANTON_DEVREL_DIR:-$HOME/.canton-devrel}"
REGISTRY_FILE="$CANTON_DEVREL_DIR/validators.json"
REGISTRY_LOCK="$CANTON_DEVREL_DIR/.registry.lock"

_registry_ensure_dir() {
  mkdir -p "$CANTON_DEVREL_DIR"
}

_registry_skeleton() {
  echo '{"version":1,"validators":[]}'
}

# Atomic write: write to temp then rename. Reader-safe.
_registry_write_atomic() {
  local content="$1"
  _registry_ensure_dir
  local tmp="$REGISTRY_FILE.$$.tmp"
  printf '%s\n' "$content" > "$tmp"
  mv "$tmp" "$REGISTRY_FILE"
}

# Print the current registry to stdout. Returns empty skeleton if file missing.
registry_read() {
  if [ -f "$REGISTRY_FILE" ]; then
    cat "$REGISTRY_FILE"
  else
    _registry_skeleton
  fi
}

# Acquire the registry lock, run a function, release.
# Uses flock if available; mkdir-based fallback otherwise.
registry_with_lock() {
  _registry_ensure_dir
  if command -v flock >/dev/null 2>&1; then
    (
      flock 9
      "$@"
    ) 9>"$REGISTRY_LOCK"
  else
    local lockdir="${REGISTRY_LOCK}.d"
    local tries=0
    while ! mkdir "$lockdir" 2>/dev/null; do
      tries=$((tries+1))
      if [ "$tries" -gt 300 ]; then
        echo "registry: could not acquire lock after 30s" >&2
        return 1
      fi
      sleep 0.1
    done
    trap "rmdir '$lockdir' 2>/dev/null" RETURN
    "$@"
    rmdir "$lockdir" 2>/dev/null
    trap - RETURN
  fi
}

# Insert or update a validator entry.
# Args: name type port_base party_hint running
# type=builtin|custom ; port_base may be empty string for builtins.
registry_upsert_validator() {
  local name="$1" type="$2" port_base="$3" party_hint="$4" running="$5"
  local current
  current=$(registry_read)
  local new
  new=$(echo "$current" | jq \
    --arg name "$name" --arg type "$type" \
    --argjson port_base "${port_base:-null}" \
    --arg party_hint "$party_hint" \
    --argjson running "$running" \
    '.validators = ((.validators | map(select(.name != $name))) +
       [{name:$name, type:$type, port_base:$port_base, party_hint:$party_hint, running:$running}])')
  _registry_write_atomic "$new"
}

# Mark a single field on an existing entry. Field must be string "running" or numeric "port_base".
registry_set_running() {
  local name="$1" running="$2"
  local current
  current=$(registry_read)
  local new
  new=$(echo "$current" | jq --arg name "$name" --argjson running "$running" \
    '(.validators[] | select(.name == $name) | .running) = $running')
  _registry_write_atomic "$new"
}

registry_remove_validator() {
  local name="$1"
  local current
  current=$(registry_read)
  local new
  new=$(echo "$current" | jq --arg name "$name" \
    '.validators = (.validators | map(select(.name != $name)))')
  _registry_write_atomic "$new"
}

# Return a single entry's JSON to stdout. Exit non-zero if absent.
registry_get() {
  local name="$1"
  local hit
  hit=$(registry_read | jq -c --arg name "$name" '.validators[] | select(.name == $name)')
  if [ -z "$hit" ]; then
    return 1
  fi
  printf '%s\n' "$hit"
}

# Print one validator name per line for entries where running=true.
registry_list_running() {
  registry_read | jq -r '.validators[] | select(.running == true) | .name'
}

# Print all custom validator names (running or not), one per line.
registry_list_customs() {
  registry_read | jq -r '.validators[] | select(.type == "custom") | .name'
}
