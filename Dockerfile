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
COPY entrypoint.sh /usr/local/bin/code-server-entrypoint.sh
RUN chmod +x /usr/local/bin/code-server-entrypoint.sh

ENTRYPOINT ["/bin/bash", "/usr/local/bin/code-server-entrypoint.sh"]
