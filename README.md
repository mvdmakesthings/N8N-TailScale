# N8N-TailScale

A hardened Docker Compose stack that pairs [n8n](https://n8n.io/) workflow automation with GPU-accelerated [Ollama](https://ollama.com/) inference, exposed exclusively through a [Tailscale](https://tailscale.com/) encrypted mesh network. Zero ports are published to the host. All traffic flows over WireGuard.

Built for sharing a home GPU rig with a trusted client — securely, with one command.

---

## Table of Contents

- [Architecture](#architecture)
- [Prerequisites](#prerequisites)
- [Quick Start](#quick-start)
- [Configuration Reference](#configuration-reference)
- [Connecting n8n to Ollama](#connecting-n8n-to-ollama)
- [Managing Models](#managing-models)
- [Tailscale ACL Policy](#tailscale-acl-policy)
- [Security Model](#security-model)
- [Network Topology](#network-topology)
- [Operations](#operations)
- [Troubleshooting](#troubleshooting)
- [Contributing](#contributing)
- [License](#license)

---

## Architecture

```
  Client's device
         │
         │  https://<hostname>.<tailnet>.ts.net
         │  WireGuard-encrypted tunnel
         │
┌────────┼──────────────────────────────────────────────────────┐
│ Docker │Compose stack                                         │
│        │                                                      │
│  ┌─────┴──────────┐                                          │
│  │   tailscale    │  Terminates HTTPS (auto-provisioned TLS) │
│  │   sidecar      │  Reverse-proxies to n8n on :5678         │
│  └─────┬──────────┘                                          │
│        │  frontend network                                    │
│  ┌─────┴──────────┐                                          │
│  │      n8n       │  Workflow engine   (sandboxed container)  │
│  │                │  Internet access   (for external APIs)    │
│  └─────┬──────────┘                                          │
│        │  backend network  (internal — no internet)           │
│  ┌─────┴──────────┐                                          │
│  │    ollama      │  LLM inference on NVIDIA GPU              │
│  │                │  Air-gapped — no outbound connectivity    │
│  └────────────────┘                                          │
│                                                               │
│  Published ports: none                                        │
└───────────────────────────────────────────────────────────────┘
```

| Service | Image | Network | Internet | GPU |
|---------|-------|---------|----------|-----|
| `tailscale` | `tailscale/tailscale` | frontend | Yes | No |
| `n8n` | `n8nio/n8n` | frontend + backend | Yes | No |
| `ollama` | `ollama/ollama` | backend | No | Yes |
| `ollama-init` | `ollama/ollama` | frontend | Yes (model pull only) | Yes |

---

## Prerequisites

| Requirement | Minimum | Verify with |
|-------------|---------|------------|
| Docker Engine | 24.0+ | `docker --version` |
| Docker Compose | v2.20+ | `docker compose version` |
| NVIDIA driver | 525+ | `nvidia-smi` |
| NVIDIA Container Toolkit | 1.14+ | `nvidia-ctk --version` |
| NVIDIA GPU VRAM | 8 GB (24 GB recommended) | `nvidia-smi` |
| Tailscale account | Free tier is sufficient | [tailscale.com](https://tailscale.com/) |

**Verify GPU passthrough into Docker:**

```bash
docker run --rm --gpus all nvidia/cuda:12.0-base nvidia-smi
```

If this prints your GPU details, you're ready. If not, see the [NVIDIA Container Toolkit installation guide](https://docs.nvidia.com/datacenter/cloud-native/container-toolkit/latest/install-guide.html).

---

## Quick Start

### 1. Clone the repository

```bash
git clone git@github.com:mvdmakesthings/N8N-TailScale.git
cd N8N-TailScale
```

### 2. Create your environment file

```bash
cp .env.example .env
```

Open `.env` and fill in every value. See the [Configuration Reference](#configuration-reference) below for details on each variable.

### 3. Generate secrets

```bash
# Paste these values into your .env
openssl rand -hex 32   # → N8N_ENCRYPTION_KEY
openssl rand -hex 32   # → N8N_USER_MANAGEMENT_JWT_SECRET
```

### 4. Generate a Tailscale auth key

1. Open the [Tailscale admin console](https://login.tailscale.com/admin/settings/keys).
2. Click **Generate auth key**.
3. Enable **Reusable** (recommended — avoids re-auth on container restart).
4. Copy the key into `TS_AUTHKEY` in your `.env`.

### 5. Start the stack

```bash
docker compose up -d
```

On the first run, `ollama-init` downloads the `llama3.1:8b` model (~4.7 GB). Monitor progress:

```bash
docker compose logs -f ollama-init
```

### 6. Open n8n

Navigate to `https://<TS_HOSTNAME>.<your-tailnet>.ts.net` from any device on your Tailscale network. n8n will prompt you to create an owner account on first visit.

---

## Configuration Reference

All configuration is stored in a `.env` file (never committed to version control).

| Variable | Required | Default | Description |
|----------|----------|---------|-------------|
| `TS_AUTHKEY` | Yes | — | Tailscale auth key. Generate at [admin console](https://login.tailscale.com/admin/settings/keys). Use a **reusable** key to survive restarts. |
| `TS_HOSTNAME` | No | `n8n-gpu` | The machine name on your tailnet. Determines the URL: `https://<value>.<tailnet>.ts.net`. |
| `N8N_ENCRYPTION_KEY` | Yes | — | Encrypts stored credentials in n8n's SQLite database. Generate with `openssl rand -hex 32`. |
| `N8N_USER_MANAGEMENT_JWT_SECRET` | Yes | — | Signs n8n session tokens. Generate with `openssl rand -hex 32`. |
| `WEBHOOK_URL` | Yes | — | Full Tailscale HTTPS URL (e.g., `https://n8n-gpu.tail1234.ts.net`). n8n uses this to generate correct webhook callback URLs. |
| `OLLAMA_DATA_PATH` | No | `/mnt/d/Models/ollama` | Host path for Ollama model storage. Uses a bind mount so models can live on a separate drive. |

> **Important:** If `N8N_ENCRYPTION_KEY` is lost or changed, all saved credentials in n8n become unreadable. Back up your `.env` securely.

---

## Connecting n8n to Ollama

n8n's AI Agent nodes require a one-time credential setup:

1. Log in to n8n.
2. Navigate to **Settings > Credentials > Add Credential**.
3. Search for **Ollama API**.
4. Set the **Base URL** to:
   ```
   http://ollama:11434
   ```
5. Click **Save**.

The `llama3.1:8b` model is pre-loaded and ready to use with the **AI Agent**, **Ollama Chat Model**, and **Ollama Embeddings** nodes.

---

## Managing Models

The Ollama service runs on an air-gapped Docker network (`internal: true`) and cannot pull models directly from the internet. A helper script is provided that temporarily connects Ollama to the internet, pulls the requested models, then disconnects it.

Models are stored on the host filesystem via a bind mount (default: `/mnt/d/Models/ollama`). Configure the path with `OLLAMA_DATA_PATH` in your `.env`.

### Pull a new model

```bash
./scripts/pull-model.sh <model>
```

Pull multiple models at once:

```bash
./scripts/pull-model.sh mistral:7b codellama:34b
```

The script handles the network connect/disconnect cycle automatically and restores isolation even if the pull fails.

### List installed models

```bash
./scripts/pull-model.sh --list
```

### Recommended models for 24 GB VRAM

| Model | VRAM | Strengths |
|-------|------|-----------|
| `llama3.1:8b` | ~5 GB | Fast general-purpose (pre-installed) |
| `mistral:7b` | ~4 GB | Efficient, strong reasoning |
| `codellama:34b` | ~18 GB | Code generation and analysis |
| `deepseek-coder-v2:16b` | ~10 GB | Code-focused, multilingual |
| `qwen2.5:32b` | ~20 GB | High-quality general-purpose |
| `qwen3-vl` | ~6 GB | Vision-language, image understanding |

Loaded models share VRAM. Ollama automatically unloads idle models, but keep total active model size under 24 GB to avoid OOM.

### Remove a model

```bash
docker exec ollama ollama rm <model>
```

---

## Tailscale ACL Policy

By default, devices on a tailnet can reach each other on all ports. Restrict your client's access to only the n8n HTTPS endpoint by configuring an [ACL policy](https://login.tailscale.com/admin/acls):

```jsonc
{
  "acls": [
    // Client can only reach n8n over HTTPS
    {
      "action": "accept",
      "src": ["client-device"],
      "dst": ["<TS_HOSTNAME>:443"]
    }

    // Add your own device rules below
  ]
}
```

| Placeholder | Replace with |
|-------------|-------------|
| `client-device` | Your client's device name or Tailscale identity |
| `<TS_HOSTNAME>` | The value of `TS_HOSTNAME` in your `.env` |

### Onboarding a client

1. Have them create a Tailscale account at [tailscale.com](https://tailscale.com/).
2. Invite them to your tailnet from the [admin console](https://login.tailscale.com/admin/users).
3. They install Tailscale on their device and join.
4. Add their device to your ACL policy (above).
5. Share the URL: `https://<TS_HOSTNAME>.<your-tailnet>.ts.net`.

---

## Security Model

This stack implements defense-in-depth across five layers:

### Layer 1 — Network perimeter

- **Zero published ports.** No service binds to the host's network interfaces.
- All ingress flows through the Tailscale WireGuard tunnel — encrypted, authenticated, and ACL-controlled.
- The host machine and home LAN are never exposed to the internet.

### Layer 2 — Tailscale access control

- Tailscale ACLs restrict which devices can reach the sidecar and on which ports.
- A client's device can be scoped to `<TS_HOSTNAME>:443` only — no lateral movement to other tailnet nodes or the host.

### Layer 3 — TLS and authentication

- Tailscale auto-provisions a valid TLS certificate (via Let's Encrypt) for the `*.ts.net` hostname.
- n8n enforces its own user authentication. The client must log in with n8n credentials.

### Layer 4 — Container sandboxing (n8n)

| Control | Effect |
|---------|--------|
| `read_only: true` | Root filesystem is immutable; prevents persistent tampering |
| `tmpfs: /tmp` | Ephemeral scratch space only |
| `cap_drop: [ALL]` | All Linux capabilities removed |
| `no-new-privileges` | Blocks privilege escalation via setuid/setgid |
| `memory: 2G` / `cpus: 2.0` | Prevents resource exhaustion from runaway workflows |
| No GPU access | GPU is reserved exclusively for Ollama |

### Layer 5 — Network isolation (Ollama)

- Ollama runs on a Docker network with `internal: true` — **no internet access whatsoever**.
- It is reachable only by n8n over the shared `backend` network.
- This prevents Ollama from being used as a pivot for data exfiltration, even if n8n's Code node is compromised.

### Known trade-offs

| Risk | Mitigation |
|------|-----------|
| n8n Code node can make outbound HTTP requests | Acceptable at the trust level between host owner and client; container isolation prevents host access |
| Tailscale auth keys expire | Use reusable keys; rotate in `.env` and restart |
| VRAM contention with large models | Start small (`llama3.1:8b` = 5 GB); document limits |

---

## Network Topology

```
┌──────────── frontend (bridge) ─────────────────────────┐
│                                                         │
│   tailscale ──── n8n ─────────────────────── Internet   │
│                   │                                     │
└───────────────────┼─────────────────────────────────────┘
                    │
┌───────────────────┼─────────────────────────────────────┐
│                   │       backend (bridge, internal)     │
│                   │                                      │
│                 ollama                      No Internet   │
│                                                          │
└──────────────────────────────────────────────────────────┘
```

- **`frontend`** — Standard bridge network with outbound internet. Hosts Tailscale (needs the mesh), n8n (needs external API access), and `ollama-init` (needs to download models on first run).
- **`backend`** — Internal-only bridge. No route to the internet. Hosts Ollama for inference. n8n bridges both networks to reach Ollama.

---

## Operations

### Start the stack

```bash
docker compose up -d
```

### Stop the stack (preserves data)

```bash
docker compose down
```

### View logs

```bash
docker compose logs -f              # all services
docker compose logs -f n8n          # n8n only
docker compose logs -f ollama       # ollama only
docker compose logs -f tailscale    # tailscale sidecar
```

### Restart a single service

```bash
docker compose restart n8n
```

### Update images

```bash
docker compose pull
docker compose up -d
```

### Full reset (destroys all data)

```bash
docker compose down -v
```

> **Warning:** This deletes n8n workflows, credentials, and execution history. Ollama models are stored on the host filesystem (`OLLAMA_DATA_PATH`) and are **not** affected by `docker compose down -v`.

### Back up n8n data

```bash
docker run --rm -v n8n-data:/data -v "$(pwd)":/backup \
  alpine tar czf /backup/n8n-backup-$(date +%Y%m%d).tar.gz -C /data .
```

### Back up Ollama models

Ollama models are stored directly on the host at `OLLAMA_DATA_PATH` (default: `/mnt/d/Models/ollama`). Back them up with standard filesystem tools:

```bash
tar czf ollama-backup-$(date +%Y%m%d).tar.gz -C /mnt/d/Models/ollama .
```

---

## Troubleshooting

### `ollama-init` fails or hangs

The init container needs internet access to pull models. Check that the `frontend` network has outbound connectivity:

```bash
docker compose logs ollama-init
```

If the model pull stalled, restart it:

```bash
docker compose up -d ollama-init
```

### n8n can't reach Ollama

Verify both services are on the `backend` network:

```bash
docker network inspect n8n-tailscale_backend
```

Test connectivity from inside the n8n container:

```bash
docker compose exec n8n wget -qO- http://ollama:11434/api/tags
```

### Tailscale node doesn't appear on the tailnet

Check the auth key:

```bash
docker compose logs tailscale
```

Common causes:
- Expired or single-use auth key (regenerate a **reusable** key)
- Incorrect `TS_AUTHKEY` in `.env`

### GPU not detected by Ollama

```bash
docker compose exec ollama nvidia-smi
```

If this fails, verify the NVIDIA Container Toolkit is installed and the Docker daemon was restarted after installation:

```bash
sudo systemctl restart docker
```

### n8n container crashes with permission errors

The `read_only` filesystem requires that all writable paths are explicitly mounted. If n8n updates introduce new write paths, add them as `tmpfs` mounts in `docker-compose.yml`:

```yaml
tmpfs:
  - /tmp
  - /home/node/.cache    # example: add if needed
```

---

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for guidelines on reporting issues, suggesting features, and submitting pull requests.

## License

This project is licensed under the MIT License. See [LICENSE](LICENSE) for details.
