# code-server-docker

Browser-based VS Code (via [code-server](https://github.com/coder/code-server)) running in Docker, with a full dev toolchain installed into a persisted home directory.

## Toolchain (installed on first start, persisted across restarts)

| Tool | How |
|------|-----|
| Go | Latest stable, arch-detected |
| Rust | via rustup, minimal profile |
| Python 3 | system + virtualenv at `~/.venv` |
| Node.js v22 | system install (LTS) |
| GitHub CLI (`gh`) | Latest release, arch-detected |
| Claude Code | Native install |
| OpenAI Codex, Task Master | npm global |
| Oh My Zsh | Default shell in terminal |

## Quick start

```bash
cp .env.example .env
# Edit .env — set PASSWORD and PROJECTS_DIR at minimum
docker compose build
docker compose up -d
```

Open `http://localhost:8929` (or `https://` if HTTPS=1).

## Configuration

All settings live in `.env`. Copy `.env.example` to get started.

| Variable | Default | Description |
|----------|---------|-------------|
| `PASSWORD` | *(required)* | Login password for code-server |
| `PUID` | `1000` | Host UID — run `id -u` to find yours |
| `PGID` | `1000` | Host GID — run `id -g` to find yours |
| `TZ` | `Asia/Singapore` | Timezone |
| `DATA_DIR` | `./data/home` | Host path → `/home/coder` (home, tools, config) |
| `PROJECTS_DIR` | `./data/projects` | Host path → `/home/coder/dev/projects` (your code) |
| `PORT` | `8929` | Host port to expose code-server on |
| `HTTPS` | `0` | Set to `1` for self-signed HTTPS |
| `UPDATE_ON_START` | `1` | Auto-update Claude Code and npm agents on start |
| `NGINX_NETWORK` | `nginx` | External Docker network name (nginx overlay only) |

## HTTPS (self-signed)

```bash
# .env
HTTPS=1
```

Restart the container. Open `https://localhost:PORT`, click **Advanced → Proceed** to bypass the browser warning.

The self-signed certificate is generated once by code-server and persisted in `DATA_DIR`.

## Nginx reverse proxy

Use the nginx overlay to attach to an existing nginx Docker network instead of publishing a port:

```bash
docker compose -f docker-compose.yml -f docker-compose.nginx.yml up -d
```

Set `NGINX_NETWORK` in `.env` if your network isn't named `nginx`.

## Colima (macOS)

This setup runs on [Colima](https://github.com/abiosoft/colima) (ARM64). Claude Code installation requires memory — if it gets OOM-killed on first start, increase Colima's memory and restart:

```bash
colima stop
colima start --memory 4
docker compose up -d
```

The install is skipped on subsequent starts once Claude Code is in `DATA_DIR`.

## Volumes

| Container path | Purpose |
|----------------|---------|
| `/home/coder` | Home dir — all toolchains install here; persists between rebuilds |
| `/home/coder/dev/projects` | Your project files (bind-mounted from host) |
