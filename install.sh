#!/usr/bin/env bash

set -euo pipefail
REPO="Jatinp26/Canton-Builder-Tool"
INSTALL_DIR="$HOME/.canton-builder"
BIN_DIR="$HOME/.local/bin"
VERSION="0.1.0"
BOLD='\033[1m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
CYAN='\033[0;36m'
NC='\033[0m'
print_banner() {
  echo ""
  echo -e "${CYAN}${BOLD}┌───────────────────────────────────────────┐${NC}"
  echo -e "${CYAN}${BOLD}│ Canton Builder Tool Installer v${VERSION} │${NC}"
  echo -e "${CYAN}${BOLD}└───────────────────────────────────────────┘${NC}"
  echo ""
}
ok()   { echo -e "${GREEN}✓${NC}  $*"; }
warn() { echo -e "${YELLOW}⚠${NC}  $*"; }
err()  { echo -e "${RED}✗${NC}  $*"; }
step() { echo -e "${BOLD}▶${NC}  $*"; }
print_banner
OS="$(uname -s)"
case "$OS" in
  Darwin) ok "macOS detected" ;;
  Linux)  ok "Linux detected" ;;
  *)
    err "Unsupported OS: $OS"
    echo "  canton builder supports macOS and Linux only."
    echo "  Windows: use WSL 2."
    exit 1
    ;;
esac
ARCH="$(uname -m)"
case "$ARCH" in
  x86_64|amd64) ok "Architecture: x86_64" ;;
  arm64|aarch64) ok "Architecture: arm64 (Apple Silicon / ARM)" ;;
  *)
    err "Unsupported architecture: $ARCH"
    exit 1
    ;;
esac
echo ""
step "Checking dependencies..."
echo ""
MISSING_DEPS=()
check_dep() {
  local cmd="$1"
  local install_hint="$2"
  if command -v "$cmd" &>/dev/null; then
    ok "$cmd found ($(command -v "$cmd"))"
  else
    err "$cmd not found"
    warn "  Install: $install_hint"
    MISSING_DEPS+=("$cmd")
  fi
}

check_dep "docker"  "Install Docker Desktop from https://www.docker.com/products/docker-desktop/"
check_dep "curl"    "brew install curl  (macOS) | sudo apt install curl  (Linux)"
check_dep "jq"      "brew install jq    (macOS) | sudo apt install jq    (Linux)"
check_dep "git"     "brew install git   (macOS) | sudo apt install git   (Linux)"
echo ""
if [ ${#MISSING_DEPS[@]} -gt 0 ]; then
  err "Missing required dependencies: ${MISSING_DEPS[*]}"
  echo "  Install them and re-run the installer."
  exit 1
fi

if ! docker info &>/dev/null; then
  err "Docker is installed but not running. Start Docker Desktop and re-run."
  exit 1
fi
ok "Docker is running"

if ! docker compose version &>/dev/null; then
  err "Docker Compose v2 not found. Update Docker Desktop (it's included in recent versions)."
  exit 1
fi
ok "Docker Compose v2 found"
DOCKER_MEMORY_BYTES=$(docker info --format '{{.MemTotal}}' 2>/dev/null || echo 0)
DOCKER_MEMORY_GB=$(( DOCKER_MEMORY_BYTES / 1024 / 1024 / 1024 ))
if [ "$DOCKER_MEMORY_GB" -lt 7 ]; then
  warn "Docker has ~${DOCKER_MEMORY_GB}GB memory. LocalNet needs at least 8GB."
  warn "Go to Docker Desktop Settings and Resources then Memory and increase it."
else
  ok "Docker memory: ~${DOCKER_MEMORY_GB}GB"
fi
echo ""
step "Installing canton builder tool to $INSTALL_DIR..."
echo ""

if [ -d "$INSTALL_DIR" ]; then
  warn "Existing installation found at $INSTALL_DIR — upgrading."
  rm -rf "$INSTALL_DIR"
fi

if command -v git &>/dev/null; then
  git clone --depth=1 --quiet \
    "https://github.com/${REPO}.git" \
    "$INSTALL_DIR" 2>/dev/null || {
      warn "git clone failed, trying tarball download..."
      mkdir -p "$INSTALL_DIR"
      curl -fsSL "https://github.com/${REPO}/archive/refs/heads/main.tar.gz" | \
        tar -xz --strip-components=1 -C "$INSTALL_DIR"
    }
else
  mkdir -p "$INSTALL_DIR"
  curl -fsSL "https://github.com/${REPO}/archive/refs/heads/main.tar.gz" | \
    tar -xz --strip-components=1 -C "$INSTALL_DIR"
fi
ok "Downloaded to $INSTALL_DIR"
if [ ! -f "$INSTALL_DIR/.env" ]; then
  cp "$INSTALL_DIR/.env.example" "$INSTALL_DIR/.env"
  ok "Created .env from .env.example"
else
  ok ".env already exists — skipping (edit $INSTALL_DIR/.env to change settings)"
fi
chmod +x "$INSTALL_DIR/canton"
chmod +x "$INSTALL_DIR/scripts/"*.sh
chmod +x "$INSTALL_DIR/scripts/lib/"*.sh 2>/dev/null || true
step "Setting up PATH..."
echo ""
mkdir -p "$BIN_DIR"
ln -sf "$INSTALL_DIR/canton" "$BIN_DIR/canton"
ok "Symlinked: $BIN_DIR/canton → $INSTALL_DIR/canton"
SHELL_NAME="$(basename "$SHELL")"
PATH_LINE="export PATH=\"\$HOME/.local/bin:\$PATH\""
CANTON_ENV_LINE="export CANTON_DEVREL_DIR=\"$INSTALL_DIR\""
add_to_shell_rc() {
  local rc_file="$1"
  if [ -f "$rc_file" ]; then
    if ! grep -q '.local/bin' "$rc_file" 2>/dev/null; then
      echo "" >> "$rc_file"
      echo "# canton builder" >> "$rc_file"
      echo "$PATH_LINE" >> "$rc_file"
      echo "$CANTON_ENV_LINE" >> "$rc_file"
      ok "Added to $rc_file"
    else
      ok "$rc_file already has ~/.local/bin in PATH"
      if ! grep -q 'CANTON_DEVREL_DIR' "$rc_file" 2>/dev/null; then
        echo "$CANTON_ENV_LINE" >> "$rc_file"
      fi
    fi
  fi
}

case "$SHELL_NAME" in
  zsh)
    add_to_shell_rc "$HOME/.zshrc"
    ;;
  bash)
    add_to_shell_rc "$HOME/.bashrc"
    add_to_shell_rc "$HOME/.bash_profile"
    ;;
  fish)
    warn "Fish shell detected. Add this manually to ~/.config/fish/config.fish:"
    echo "    set -x PATH \$HOME/.local/bin \$PATH"
    echo "    set -x CANTON_DEVREL_DIR $INSTALL_DIR"
    ;;
  *)
    warn "Unknown shell: $SHELL_NAME. Add this to your shell RC file manually:"
    echo "    $PATH_LINE"
    echo "    $CANTON_ENV_LINE"
    ;;
esac

echo ""
step "Checking /etc/hosts for *.localhost domains..."
echo ""
HOSTS_NEEDED=()
for domain in wallet.localhost scan.localhost keycloak.localhost; do
  if ! grep -q "$domain" /etc/hosts 2>/dev/null; then
    HOSTS_NEEDED+=("$domain")
  fi
done

if [ ${#HOSTS_NEEDED[@]} -gt 0 ]; then
  warn "Missing from /etc/hosts: ${HOSTS_NEEDED[*]}"
  echo ""
  read -rp "  Add them now? (requires sudo) [y/N] " add_hosts
  add_hosts_lower="$(echo "$add_hosts" | tr '[:upper:]' '[:lower:]')"
  if [ "$add_hosts_lower" = "y" ]; then
    echo "127.0.0.1  wallet.localhost scan.localhost keycloak.localhost" | \
      sudo tee -a /etc/hosts > /dev/null
    ok "Added to /etc/hosts"
  else
    warn "Skipped. Wallet and Scan UIs may not resolve in the browser."
    warn "Add manually: echo '127.0.0.1  wallet.localhost scan.localhost keycloak.localhost' | sudo tee -a /etc/hosts"
  fi
else
  ok "All *.localhost domains already in /etc/hosts"
fi

echo ""
echo -e "${GREEN}${BOLD}┌─────────────────────────────────────────┐${NC}"
echo -e "${GREEN}${BOLD}│     Canton Builder Tool Installed!      │${NC}"
echo -e "${GREEN}${BOLD}└─────────────────────────────────────────┘${NC}"
echo ""
echo "  Reload your shell, then run:"
echo ""
echo -e "    ${BOLD}canton builder start${NC}"
echo ""
echo "  Or reload now:"
case "$SHELL_NAME" in
  zsh)  echo "    source ~/.zshrc" ;;
  bash) echo "    source ~/.bashrc" ;;
  *)    echo "    (reload your shell)" ;;
esac
echo ""
echo "  Full command reference: canton builder --help"
echo ""