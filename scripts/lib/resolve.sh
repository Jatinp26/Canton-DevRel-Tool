#!/usr/bin/env bash
# Resolve the active validator set from CLI flags + registry + DEFAULT_VALIDATORS env.
# Prints four `KEY=value` lines to stdout. Exits non-zero with a message on error.
[[ -n "${_RESOLVE_SH_LOADED:-}" ]] && return; _RESOLVE_SH_LOADED=1

# Built-in validator names recognized by `--absolute`/`--with`/`--without` and registry.
BUILTIN_NAMES=(app-provider app-user)

_is_builtin() {
  local n="$1" b
  for b in "${BUILTIN_NAMES[@]}"; do [[ "$n" == "$b" ]] && return 0; done
  return 1
}

_is_custom_in_registry() {
  local n="$1"
  registry_get "$n" >/dev/null 2>&1 && \
    [ "$(registry_get "$n" | jq -r .type)" = "custom" ]
}

# Convert comma-separated list to newline-separated.
_split() { echo "$1" | tr ',' '\n' | sed '/^$/d'; }

# Reject sv and unknown names. $1 = list of names (newline-separated).
_validate_names() {
  local n
  while IFS= read -r n; do
    [ -z "$n" ] && continue
    if [[ "$n" == "sv" ]]; then
      echo "sv is infrastructure; always on" >&2; return 1
    fi
    if _is_builtin "$n"; then continue; fi
    if _is_custom_in_registry "$n"; then continue; fi
    echo "no such validator '$n'; run \`canton devrel validator list\`" >&2; return 1
  done <<< "$1"
}

resolve_active_set() {
  local absolute="" with="" without=""
  while [ $# -gt 0 ]; do
    case "$1" in
      --absolute) absolute="$2"; shift 2 ;;
      --with)     with="$2";     shift 2 ;;
      --without)  without="$2";  shift 2 ;;
      *) echo "unknown resolve flag: $1" >&2; return 1 ;;
    esac
  done

  if [ -n "$absolute" ] && { [ -n "$with" ] || [ -n "$without" ]; }; then
    echo "--validators/--only is absolute; use only --with/--without to modify" >&2
    return 1
  fi

  local active_names=""

  if [ -n "$absolute" ]; then
    _validate_names "$(_split "$absolute")" || return 1
    active_names="$absolute"
  else
    # Step 2: registry running set
    local running
    running=$(registry_list_running 2>/dev/null | paste -sd, -)
    if [ -n "$running" ]; then
      active_names="$running"
    elif [ -n "${DEFAULT_VALIDATORS:-}" ]; then
      _validate_names "$(_split "$DEFAULT_VALIDATORS")" || return 1
      active_names="$DEFAULT_VALIDATORS"
    else
      active_names="app-provider"
    fi
    # Apply --with / --without
    if [ -n "$with" ]; then
      _validate_names "$(_split "$with")" || return 1
      local item
      while IFS= read -r item; do
        [ -z "$item" ] && continue
        if ! echo ",$active_names," | grep -q ",$item,"; then
          active_names="${active_names:+$active_names,}$item"
        fi
      done <<< "$(_split "$with")"
    fi
    if [ -n "$without" ]; then
      # sv check is enough; unknown names in --without are a no-op? Spec §3.1 says reject unknown.
      _validate_names "$(_split "$without")" || return 1
      local item
      while IFS= read -r item; do
        [ -z "$item" ] && continue
        active_names=$(echo "$active_names" | tr ',' '\n' | grep -vx "$item" | paste -sd, -)
      done <<< "$(_split "$without")"
    fi
  fi

  # Bucket into builtins (profile flags) and customs.
  local app_provider=off app_user=off customs=""
  local n
  while IFS= read -r n; do
    [ -z "$n" ] && continue
    case "$n" in
      app-provider) app_provider=on ;;
      app-user)     app_user=on ;;
      *)            customs="${customs:+$customs,}$n" ;;
    esac
  done < <(_split "$active_names")

  echo "SV_PROFILE=on"
  echo "APP_PROVIDER_PROFILE=$app_provider"
  echo "APP_USER_PROFILE=$app_user"
  echo "CUSTOMS=$customs"
}
