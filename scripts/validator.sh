#!/usr/bin/env bash
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$REPO_DIR/scripts/lib/validator.sh"

VERB="${1:-}"
shift || true

case "$VERB" in
  list)  validator_list ;;
  info)  validator_info "$@" ;;
  add)   validator_add "$@" ;;
  start) validator_start "$@" ;;
  stop)  validator_stop "$@" ;;
  rm)    validator_rm "$@" ;;
  ""|help|--help|-h)
    cat <<EOF
USAGE
  canton builder validator <verb> [args]

VERBS
  list                          List all validators (built-in + custom)
  info <name>                   Show ports, wallet URL, party hint for one validator
  add <name> [--port-base N]    Register and start a new custom validator
  start <name>                  Start an existing validator
  stop <name>                   Stop a validator (data preserved)
  rm <name> [--force]           Remove a custom validator (built-ins can't be removed)

EXAMPLES
  canton builder validator list
  canton builder validator add acme
  canton builder validator add bob --port-base 7900
  canton builder validator info acme
  canton builder validator stop acme
  canton builder validator rm acme
EOF
    ;;
  *)
    echo "unknown verb: $VERB" >&2
    echo "run 'canton builder validator help' for usage" >&2
    exit 1
    ;;
esac
