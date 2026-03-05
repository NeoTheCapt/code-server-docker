FROM codercom/code-server:latest

USER root

# Base deps (toolchains/agents will be installed into persisted HOME)
RUN apt-get update && apt-get install -y --no-install-recommends \
    bash ca-certificates tzdata \
    curl wget git openssh-client \
    zsh \
    jq \
    python3 python3-pip python3-venv \
    make g++ build-essential \
    ripgrep fd-find fzf \
    unzip xz-utils \
    tmux \
    openjdk-17-jdk-headless maven \
  && rm -rf /var/lib/apt/lists/*

# Install Node.js (system) - pinned to v22.x (LTS line)
RUN set -eux; \
  ARCH="$(uname -m)"; \
  case "$ARCH" in \
    aarch64|arm64) NODE_ARCH=arm64 ;; \
    x86_64|amd64) NODE_ARCH=x64 ;; \
    *) echo "Unsupported arch: $ARCH"; exit 1 ;; \
  esac; \
  NODE_VER="$(curl -fsSL https://nodejs.org/dist/index.json | jq -r '[.[] | select(.version|test("^v22\\."))][0].version')"; \
  test -n "$NODE_VER" && [ "$NODE_VER" != "null" ]; \
  echo "Installing Node $NODE_VER for $NODE_ARCH"; \
  curl -fsSL "https://nodejs.org/dist/${NODE_VER}/node-${NODE_VER}-linux-${NODE_ARCH}.tar.xz" -o /tmp/node.tar.xz; \
  tar -C /usr/local --strip-components=1 -xJf /tmp/node.tar.xz; \
  rm -f /tmp/node.tar.xz; \
  node -v; npm -v

# Install GitHub CLI (gh)
RUN set -eux; \
  ARCH="$(uname -m)"; \
  case "$ARCH" in \
    aarch64|arm64) GH_ARCH=arm64 ;; \
    x86_64|amd64) GH_ARCH=amd64 ;; \
    *) echo "Unsupported arch: $ARCH"; exit 1 ;; \
  esac; \
  GH_TAG="$(curl -fsSL https://api.github.com/repos/cli/cli/releases/latest | jq -r '.tag_name')"; \
  GH_VER="${GH_TAG#v}"; \
  echo "Installing gh $GH_VER for $GH_ARCH"; \
  curl -fsSL "https://github.com/cli/cli/releases/download/${GH_TAG}/gh_${GH_VER}_linux_${GH_ARCH}.tar.gz" -o /tmp/gh.tgz; \
  tar -C /tmp -xzf /tmp/gh.tgz; \
  install -m 0755 "/tmp/gh_${GH_VER}_linux_${GH_ARCH}/bin/gh" /usr/local/bin/gh; \
  rm -rf /tmp/gh*; \
  gh --version | head -n 1

# Entrypoint: install tools into HOME (persisted) + configure zsh + start code-server
RUN cat > /usr/local/bin/code-server-entrypoint.sh <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

export HOME="${HOME:-/home/coder}"
export TZ="${TZ:-Asia/Singapore}"

log() { echo "[entrypoint] $*"; }

ensure_dirs() {
  mkdir -p "$HOME" "$HOME/.local" "$HOME/.cache" "$HOME/.config" "$HOME/project"
}

ensure_path_exports() {
  # User-scoped installs
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
    cat >> "$HOME/.zshrc" <<'ZSH'

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
  # Make zsh default terminal in VSCode
  local settings_dir="$HOME/.local/share/code-server/User"
  mkdir -p "$settings_dir"
  local f="$settings_dir/settings.json"
  if [ ! -f "$f" ]; then
    cat > "$f" <<'JSON'
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

  local go_json go_file
  go_json=$(curl -fsSL 'https://go.dev/dl/?mode=json')
  go_file=$(echo "$go_json" | jq -r '[.[] | select(.stable==true)][0].files[] | select(.os=="linux" and .arch=="arm64" and .kind=="archive") | .filename' | head -n1)
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
  if ! command -v claude >/dev/null 2>&1; then
    log "installing Claude Code (native install)"
    curl -fsSL https://claude.ai/install.sh | bash
  fi

  if [ "${UPDATE_ON_START:-1}" = "1" ]; then
    log "updating Claude Code (native)"
    timeout 180 claude update || true
  fi
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

  if [ "${UPDATE_ON_START:-1}" = "1" ]; then
    log "updating npm agents"
    timeout 300 npm i -g @openai/codex@latest --no-audit --prefer-offline --legacy-peer-deps || true
    timeout 300 npm i -g task-master-ai@latest --no-audit --prefer-offline --legacy-peer-deps || true
  fi
}

sync_claude_rules() {
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
}

main() {
  ensure_dirs
  ensure_path_exports
  install_oh_my_zsh
  configure_code_server_terminal

  install_go_user
  install_rust_user
  install_python_user
  install_claude_native_user
  install_npm_agents_user
  sync_claude_rules

  log "starting code-server (zsh default)"
  exec /usr/bin/code-server --bind-addr 0.0.0.0:8080
}

main "$@"
EOF

RUN chmod +x /usr/local/bin/code-server-entrypoint.sh

ENTRYPOINT ["/usr/local/bin/code-server-entrypoint.sh"]
