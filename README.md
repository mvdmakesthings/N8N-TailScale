# casper-n8n

Tailscale-exposed n8n with enterprise feature bypass, connecting to the shared Ollama instance from the parent `casper` stack.

---

## Architecture

```
  Client device (any tailnet member)
         |
         |  https://<hostname>.<tailnet>.ts.net
         |  WireGuard-encrypted tunnel
         |
+--------+---------------------------------------------+
| n8n-gpu compose stack                                 |
|        |                                              |
|  +-----+----------+                                   |
|  |   tailscale    |  Terminates HTTPS (auto TLS)      |
|  |                |  Reverse-proxies to n8n:5678      |
|  +-----+----------+                                   |
|        |  frontend network (local bridge)              |
|  +-----+----------+     +--------------------+        |
|  |   casper-n8n   |     | n8n-task-runners   |        |
|  |                +---->|                    |        |
|  | Workflow engine |:5679| JS + Python code  |        |
|  +-----+----------+     +--------------------+        |
|        |                                              |
|  Published ports: none                                |
+--------+----------------------------------------------+
         |  ollama-net (external network)
         |
+--------+----------------------------------------------+
| casper compose stack                                   |
|  +----------------+                                    |
|  | casper-ollama  |  LLM inference (GPU)               |
|  +----------------+                                    |
+--------------------------------------------------------+
```

### Services

| Service | Container | Image | Networks |
|---------|-----------|-------|----------|
| `tailscale` | `tailscale` | `tailscale/tailscale:latest` | `frontend` |
| `n8n` | `casper-n8n` | `casper-n8n:<N8N_VERSION>` (custom build) | `frontend`, `ollama-net`, `n8n-net` |
| `n8n-task-runners` | `n8n-task-runners` | `n8nio/runners:<N8N_VERSION>` | `frontend` |

### Networks

| Network | Type | Purpose |
|---------|------|---------|
| `frontend` | local bridge | tailscale <-> n8n, n8n <-> task runners |
| `ollama-net` | external | n8n -> `casper-ollama` for LLM inference |
| `n8n-net` | external | shared network with `casper` stack |

### Volumes

| Volume | Mount | Purpose |
|--------|-------|---------|
| `n8n-data` | `/home/node/.n8n` | n8n workflows, credentials, SQLite DB |
| `tailscale-state` | `/var/lib/tailscale` | Tailscale node identity and keys |

---

## Prerequisites

- Docker Engine 24.0+ / Docker Compose v2.20+
- Tailscale account ([free tier works](https://tailscale.com/))
- Parent `casper` stack running -- provides:
  - `casper-ollama` container
  - `ollama-net` external network
  - `n8n-net` external network

Verify the external networks exist:

```bash
docker network ls | grep -E 'ollama-net|n8n-net'
```

---

## Quick Start

```bash
# Clone
git clone git@github.com:mvdmakesthings/casper-n8n.git
cd casper-n8n

# Configure
cp .env.example .env

# Generate secrets
openssl rand -hex 32   # -> N8N_ENCRYPTION_KEY
openssl rand -hex 32   # -> N8N_USER_MANAGEMENT_JWT_SECRET
openssl rand -hex 32   # -> N8N_RUNNERS_AUTH_TOKEN
```

Create a **reusable** Tailscale auth key at the [admin console](https://login.tailscale.com/admin/settings/keys) and paste it into `TS_AUTHKEY`.

Fill in the remaining `.env` values, then:

```bash
# Build and start (first build takes 15-30 min)
docker compose up -d --build

# Open n8n from any device on your tailnet:
# https://<TS_HOSTNAME>.<your-tailnet>.ts.net
```

n8n will prompt you to create an owner account on first visit.

---

## Environment Variables

All configuration lives in `.env` (never committed).

| Variable | Required | Default | Description |
|----------|----------|---------|-------------|
| `TS_AUTHKEY` | Yes | -- | Tailscale auth key. Use **reusable** to survive restarts. |
| `TS_HOSTNAME` | No | `n8n-gpu` | Machine name on tailnet. Determines the URL prefix. |
| `TS_EXTRA_ARGS` | No | *(empty)* | Extra args for `tailscale up` (e.g. `--advertise-tags=tag:container`). |
| `N8N_VERSION` | No | `2.8.3` | Pinned n8n version. Must match a patch-compatible release. |
| `NODE_VERSION` | No | `22` | Node.js major version for the build. |
| `N8N_ENCRYPTION_KEY` | Yes | -- | Encrypts stored credentials. Generate: `openssl rand -hex 32`. |
| `N8N_USER_MANAGEMENT_JWT_SECRET` | Yes | -- | Signs session tokens. Generate: `openssl rand -hex 32`. |
| `WEBHOOK_URL` | Yes | -- | Full Tailscale URL (e.g. `https://n8n-gpu.tail1234.ts.net`). |
| `N8N_RUNNERS_AUTH_TOKEN` | Yes | -- | Shared secret for runner <-> broker auth. Generate: `openssl rand -hex 32`. |
| `N8N_RUNNERS_MAX_CONCURRENCY` | No | `5` | Max parallel code executions per runner instance. |

> **Warning:** Losing `N8N_ENCRYPTION_KEY` makes all saved n8n credentials unreadable.

---

## Ollama Connection

Ollama is **not** managed by this stack. It runs in the parent `casper` project as `casper-ollama`. n8n reaches it via the shared `ollama-net` network.

### n8n credential setup

1. Log in to n8n -> **Settings -> Credentials -> Add Credential**
2. Search for **Ollama API**
3. Set Base URL to:
   ```
   http://casper-ollama:11434
   ```
4. Save.

### Pull a model (operates on the external casper-ollama container)

```bash
./scripts/pull-model.sh llama3.1:8b           # single model
./scripts/pull-model.sh mistral:7b qwen3-vl   # multiple models
./scripts/pull-model.sh --list                 # list installed
```

The script temporarily connects `casper-ollama` to `casper_frontend` for internet access, pulls the model, then disconnects.

---

## Custom n8n Build

The `casper-n8n` image applies a dev license bypass patch to unlock all enterprise features for home-lab use. Based on [MatrixForgeLabs/n8n-dev-license-bypass](https://github.com/MatrixForgeLabs/n8n-dev-license-bypass), forward-ported to n8n v2.x.

**For development/home-lab use only -- not production.**

### What it unlocks

- LDAP / SAML authentication
- Workflow sharing and advanced permissions
- Workflow history with unlimited retention
- Variables, external secrets, source control (Git)
- Log streaming, audit logs, worker view
- AI assistant and AI credits
- Unlimited users, triggers, and team projects

### Build

```bash
docker compose build n8n          # ~15-30 min, needs 8+ GB RAM
```

### Version update procedure

1. Set `N8N_VERSION` in `.env`
2. Rebuild: `docker compose build --no-cache n8n`
3. Pull matching runner image: `docker compose pull n8n-task-runners`
4. Restart: `docker compose up -d`

> **Note:** The runner image (`n8nio/runners`) must match the n8n version. Both use `${N8N_VERSION}`.

### Patch failure recovery

If `git apply dev-license-bypass.patch` fails during build, the n8n source at the new version has diverged. Compare the changed files against `n8n/dev-license-bypass.patch` and update the context lines. The patch was created for `2.8.3`.

---

## Security Hardening

Zero published ports -- all ingress flows through Tailscale's WireGuard tunnel.

### n8n container controls

| Control | Value | Effect |
|---------|-------|--------|
| `read_only` | `true` | Immutable root filesystem |
| `tmpfs` | `/tmp`, `/home/node/.cache` | Ephemeral scratch only |
| `cap_drop` | `ALL` | All Linux capabilities removed |
| `security_opt` | `no-new-privileges` | Blocks setuid/setgid escalation |
| `memory` | `2G` | Prevents resource exhaustion |
| `cpus` | `2.0` | CPU throttle for runaway workflows |

### Task runner container controls

| Control | Value | Effect |
|---------|-------|--------|
| `read_only` | `true` | Immutable root filesystem |
| `tmpfs` | `/tmp`, `/home/runner/.cache` | Ephemeral scratch only |
| `cap_drop` | `ALL` | All Linux capabilities removed |
| `security_opt` | `no-new-privileges` | Blocks setuid/setgid escalation |
| `memory` | `1G` | Prevents runaway code snippets |
| `cpus` | `1.0` | CPU throttle for code execution |

Restrict tailnet access further with [Tailscale ACLs](https://login.tailscale.com/admin/acls) -- scope clients to `<TS_HOSTNAME>:443` only.

---

## Operations Cheatsheet

```bash
# Start / stop
docker compose up -d
docker compose down

# Logs
docker compose logs -f              # all services
docker compose logs -f n8n          # n8n only
docker compose logs -f n8n-task-runners  # task runner only
docker compose logs -f tailscale    # tailscale only

# Rebuild n8n after version bump
docker compose build --no-cache n8n && docker compose up -d

# Restart a single service
docker compose restart n8n

# Update tailscale image
docker compose pull tailscale && docker compose up -d tailscale

# Update task runner image (must match N8N_VERSION)
docker compose pull n8n-task-runners && docker compose up -d n8n-task-runners

# Backup n8n data
docker run --rm -v n8n-data:/data -v "$(pwd)":/backup \
  alpine tar czf /backup/n8n-backup-$(date +%Y%m%d).tar.gz -C /data .

# Pull a model (on external casper-ollama container)
./scripts/pull-model.sh llama3.1:8b

# Remove a model
docker exec casper-ollama ollama rm <model>

# Full reset (destroys n8n workflows + credentials, not Ollama models)
docker compose down -v
```

---

## Troubleshooting

**n8n can't reach Ollama**

```bash
# Verify casper-ollama is on ollama-net
docker network inspect ollama-net | grep casper-ollama

# Test connectivity from n8n container
docker exec casper-n8n wget -qO- http://casper-ollama:11434/api/tags
```

If empty, ensure the `casper` stack is running and `ollama-net` exists.

**Tailscale node doesn't appear on tailnet**

```bash
docker compose logs tailscale
```

Common causes: expired or single-use auth key, incorrect `TS_AUTHKEY`.

**n8n build OOM**

Build requires 8+ GB RAM. Increase Docker's memory limit (Docker Desktop -> Settings -> Resources), close other apps, retry.

**Patch fails to apply**

```bash
grep N8N_VERSION .env   # check target version
```

Patch was created for `2.8.3`. Newer versions may require updating `n8n/dev-license-bypass.patch`.

**n8n permission errors on startup**

The `read_only` filesystem requires explicit mounts for all writable paths. If a new n8n version introduces new write paths, add them as `tmpfs` in `docker-compose.yml`.

---

## File Layout

```
casper-n8n/
├── docker-compose.yml            # 3 services, 3 networks, 2 volumes
├── .env.example                  # Environment variable template
├── .env                          # Local config (git-ignored)
├── n8n/
│   ├── Dockerfile                # Multi-stage build with license bypass
│   └── dev-license-bypass.patch  # Enterprise feature unlock
├── tailscale/
│   └── serve-config.json         # HTTPS reverse proxy -> n8n:5678
├── scripts/
│   └── pull-model.sh             # Pull models on external casper-ollama
├── CONTRIBUTING.md
└── LICENSE
```
