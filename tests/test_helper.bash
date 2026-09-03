# Shared helpers for all bats tests.
# Each test gets a fresh isolated $CANTON_DEVREL_DIR; teardown removes it.

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

setup() {
  TMPHOME="$(mktemp -d -t canton-devrel-test.XXXXXX)"
  export TMPHOME
  export CANTON_DEVREL_DIR="$TMPHOME"
  export REPO_DIR
  export DEVREL_DIR="$REPO_DIR"
  export PATH="$TMPHOME/stubs:$PATH"
  mkdir -p "$TMPHOME/stubs"
}

teardown() {
  rm -rf "$TMPHOME"
}

# Stub docker so unit tests never touch a real daemon.
# Calls are recorded one-per-line in $TMPHOME/docker-calls.
stub_docker() {
  cat > "$TMPHOME/stubs/docker" <<'EOF'
#!/usr/bin/env bash
echo "$@" >> "$TMPHOME/docker-calls"
case "$*" in
  "compose ls --format json")  echo '[]'; exit 0 ;;
  *exec*nginx*nginx*-s*reload*) exit 0 ;;
  *) exit 0 ;;
esac
EOF
  chmod +x "$TMPHOME/stubs/docker"
}

# Record arbitrary external commands the same way (curl, openssl, etc.).
stub_cmd() {
  local name="$1"
  local exit_code="${2:-0}"
  cat > "$TMPHOME/stubs/$name" <<EOF
#!/usr/bin/env bash
echo "$name \$*" >> "$TMPHOME/cmd-calls"
exit $exit_code
EOF
  chmod +x "$TMPHOME/stubs/$name"
}
