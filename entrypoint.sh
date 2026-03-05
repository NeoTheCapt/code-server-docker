#!/usr/bin/env bash
set -euo pipefail

export HOME="${HOME:-/home/coder}"
export TZ="${TZ:-Asia/Singapore}"

log() { echo "[entrypoint] $*"; }

ensure_dirs() {
  mkdir -p "$HOME" "$HOME/.local" "$HOME/.cache" "$HOME/.config" "$HOME/project"
}

ensure_path_exports() {
  export GOROOT="$HOME/.local/go"
  export GOPATH="$HOME/.local/gopath"
  export RUSTUP_HOME="$HOME/.rustup"
  export CARGO_HOME="$HOME/.cargo"
  export VIRTUAL_ENV="$HOME/.venv"
  export NPM_CONFIG_PREFIX="$HOME/.npm-global"

  export PATH="$HOME/.local/bin:$VIRTUAL_ENV/bin:$CARGO_HOME/bin:$GOROOT/bin:$NPM_CONFIG_PREFIX/bin:$PATH"
}

install_oh_my_zsh() {
  if [ ! -d "$HOME/.oh-my-zsh" ]; then
    log "installing oh-my-zsh"
    git clone --depth=1 https://github.com/ohmyzsh/ohmyzsh.git "$HOME/.oh-my-zsh" || true
  fi

  if [ ! -f "$HOME/.zshrc" ] && [ -f "$HOME/.oh-my-zsh/templates/zshrc.zsh-template" ]; then
    cp -f "$HOME/.oh-my-zsh/templates/zshrc.zsh-template" "$HOME/.zshrc" || true
  fi

  # Append our env only once
  if [ -f "$HOME/.zshrc" ] && ! grep -q "openclaw-devtools" "$HOME/.zshrc" 2>/dev/null; then
    cat >> "$HOME/.zshrc" << 'ZSH'

# openclaw-devtools
export GOROOT="$HOME/.local/go"
export GOPATH="$HOME/.local/gopath"
export RUSTUP_HOME="$HOME/.rustup"
export CARGO_HOME="$HOME/.cargo"
export VIRTUAL_ENV="$HOME/.venv"
export NPM_CONFIG_PREFIX="$HOME/.npm-global"
export PATH="$HOME/.local/bin:$VIRTUAL_ENV/bin:$CARGO_HOME/bin:$GOROOT/bin:$NPM_CONFIG_PREFIX/bin:$PATH"
ZSH
  fi
}

configure_code_server_terminal() {
  local settings_dir="$HOME/.local/share/code-server/User"
  mkdir -p "$settings_dir"
  local f="$settings_dir/settings.json"
  if [ ! -f "$f" ]; then
    cat > "$f" << 'JSON'
{
  "terminal.integrated.profiles.linux": {
    "zsh": { "path": "/usr/bin/zsh" },
    "bash": { "path": "/bin/bash" }
  },
  "terminal.integrated.defaultProfile.linux": "zsh"
}
JSON
  fi
}

install_go_user() {
  if [ -x "$GOROOT/bin/go" ]; then
    return 0
  fi
  log "installing Go into $GOROOT"
  mkdir -p "$HOME/.local"

  local machine go_arch go_json go_file
  machine="$(uname -m)"
  case "$machine" in
    aarch64|arm64) go_arch=arm64 ;;
    x86_64|amd64)  go_arch=amd64 ;;
    armv7l)        go_arch=armv6l ;;
    *) echo "Unsupported arch: $machine"; exit 1 ;;
  esac

  go_json=$(curl -fsSL 'https://go.dev/dl/?mode=json')
  go_file=$(echo "$go_json" | jq -r --arg arch "$go_arch" \
    '[.[] | select(.stable==true)][0].files[] | select(.os=="linux" and .arch==$arch and .kind=="archive") | .filename' \
    | head -n1)
  test -n "$go_file" && [ "$go_file" != "null" ]

  curl -fsSL "https://go.dev/dl/$go_file" -o /tmp/go.tgz
  rm -rf "$HOME/.local/go"
  tar -C "$HOME/.local" -xzf /tmp/go.tgz
  rm -f /tmp/go.tgz
}

install_rust_user() {
  if [ -x "$CARGO_HOME/bin/rustc" ]; then
    return 0
  fi
  log "installing rustup into $RUSTUP_HOME"
  curl -fsSL https://sh.rustup.rs | sh -s -- -y --no-modify-path --profile minimal
}

install_python_user() {
  if [ -x "$VIRTUAL_ENV/bin/python" ]; then
    return 0
  fi
  log "creating python venv at $VIRTUAL_ENV"
  python3 -m venv "$VIRTUAL_ENV"
  "$VIRTUAL_ENV/bin/pip" install --no-cache-dir -U pip setuptools wheel
  "$VIRTUAL_ENV/bin/pip" install --no-cache-dir uv ruff pytest mypy httpx tenacity orjson typer click
}

install_claude_native_user() {
  # Check both command PATH and the known install location
  if command -v claude >/dev/null 2>&1 || [ -x "$HOME/.local/bin/claude" ]; then
    return 0
  fi
  log "installing Claude Code (native install)"
  timeout 300 bash -c 'curl -fsSL https://claude.ai/install.sh | bash' || \
    log "WARNING: Claude Code install failed (OOM or network) - will retry on next start"
}

install_npm_agents_user() {
  mkdir -p "$NPM_CONFIG_PREFIX"

  if [ ! -x "$NPM_CONFIG_PREFIX/bin/codex" ]; then
    log "installing npm agents into $NPM_CONFIG_PREFIX"
    npm i -g --no-audit --prefer-offline --legacy-peer-deps \
      @openai/codex \
      task-master-ai \
      vite
  fi
}

# All update/sync operations — run in background so startup is not blocked
background_updates() {
  {
    if [ "${UPDATE_ON_START:-1}" = "1" ]; then
      # Update Claude Code
      if command -v claude >/dev/null 2>&1 || [ -x "$HOME/.local/bin/claude" ]; then
        log "bg: updating Claude Code"
        timeout 180 claude update || true
      fi

      # Update npm agents
      log "bg: updating npm agents"
      timeout 300 npm i -g @openai/codex@latest --no-audit --prefer-offline --legacy-peer-deps || true
      timeout 300 npm i -g task-master-ai@latest --no-audit --prefer-offline --legacy-peer-deps || true
    fi

    # Sync claude rules
    local repo="$HOME/.cache/everything-claude-code"
    if [ -d "$repo/.git" ]; then
      timeout 60 git -C "$repo" pull --ff-only || true
    else
      rm -rf "$repo" || true
      timeout 60 git clone --depth=1 https://github.com/affaan-m/everything-claude-code.git "$repo" || true
    fi
    mkdir -p "$HOME/.claude/rules"
    rm -rf "$HOME/.claude/rules"/* || true
    if [ -d "$repo/rules" ]; then
      cp -a "$repo/rules/." "$HOME/.claude/rules/" || true
    fi

    log "bg: updates complete"
  } &
}

background_installs() {
  {
    install_go_user
    install_rust_user
    install_python_user
    install_claude_native_user
    install_npm_agents_user
    background_updates
    log "bg: all installs complete"
  } &
}

main() {
  ensure_dirs
  ensure_path_exports

  # These are fast and affect first-launch UX — keep synchronous
  install_oh_my_zsh
  configure_code_server_terminal

  # All tool installs and updates run in background
  background_installs

  local args=(--bind-addr "0.0.0.0:8080")
  if [ "${HTTPS:-0}" = "1" ]; then
    log "HTTPS enabled (self-signed cert)"
    args+=(--cert)
  fi

  log "starting code-server"
  exec /usr/bin/code-server "${args[@]}"
}

main "$@"
