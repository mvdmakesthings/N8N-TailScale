# jlyve-n8n

A Docker Compose stack that runs n8n with GPU-accelerated Ollama, securely exposed via Tailscale. No ports are published to the host — all access goes through a Tailscale HTTPS URL.

## Architecture

```
Internet ─── Tailscale mesh (WireGuard) ─── Jason's device
                    │
        ┌───────────┴───────────┐
        │    tailscale sidecar  │  (HTTPS reverse proxy)
        └───────────┬───────────┘
                    │ http://n8n:5678
        ┌───────────┴───────────┐
        │         n8n           │  (sandboxed, internet access)
        └───────────┬───────────┘
                    │ http://ollama:11434
        ┌───────────┴───────────┐
        │        ollama         │  (GPU, no internet)
        └───────────────────────┘
```

## Prerequisites

- **Docker** with Compose v2 (`docker compose version`)
- **NVIDIA Container Toolkit** — [installation guide](https://docs.nvidia.com/datacenter/cloud-native/container-toolkit/latest/install-guide.html)
- **Tailscale account** — [sign up](https://tailscale.com/)
- **NVIDIA GPU** with sufficient VRAM (24GB recommended)

Verify GPU passthrough works:

```bash
docker run --rm --gpus all nvidia/cuda:12.0-base nvidia-smi
```

## Setup

1. **Clone this repo**

   ```bash
   git clone git@github.com:mvdmakesthings/N8N-TailScale.git
   cd N8N-TailScale
   ```

2. **Create your `.env` file**

   ```bash
   cp .env.example .env
   ```

   Fill in the values:

   | Variable | Where to get it |
   |----------|----------------|
   | `TS_AUTHKEY` | [Tailscale admin console](https://login.tailscale.com/admin/settings/keys) — generate a reusable auth key |
   | `TS_HOSTNAME` | Pick a name (e.g., `jlyve-n8n`) — this becomes part of your Tailscale URL |
   | `N8N_ENCRYPTION_KEY` | Run `openssl rand -hex 32` |
   | `N8N_USER_MANAGEMENT_JWT_SECRET` | Run `openssl rand -hex 32` |
   | `WEBHOOK_URL` | `https://<TS_HOSTNAME>.<your-tailnet>.ts.net` |

3. **Start the stack**

   ```bash
   docker compose up -d
   ```

   On first start, `ollama-init` will pull the `llama3.1:8b` model (~4.7GB). Watch progress with:

   ```bash
   docker compose logs -f ollama-init
   ```

4. **Access n8n**

   Open `https://<TS_HOSTNAME>.<your-tailnet>.ts.net` from any device on your tailnet. On first visit, n8n will prompt you to create an owner account.

## Configuring the Ollama Connection in n8n

n8n's AI agent nodes need an Ollama credential configured:

1. In n8n, go to **Settings > Credentials > Add Credential**
2. Search for **Ollama API**
3. Set the base URL to `http://ollama:11434`
4. Save — the `llama3.1:8b` model is ready to use

## Pulling Additional Models

Jason can pull more models at any time:

```bash
docker compose exec ollama ollama pull <model-name>
```

Examples:

```bash
docker compose exec ollama ollama pull mistral:7b
docker compose exec ollama ollama pull codellama:34b
docker compose exec ollama ollama pull deepseek-coder-v2:16b
```

Check available VRAM before pulling large models — 24GB total, and loaded models share this space.

To list downloaded models:

```bash
docker compose exec ollama ollama list
```

## Tailscale ACL Configuration

To restrict Jason's access to only the n8n service, add this to your [Tailscale ACL policy](https://login.tailscale.com/admin/acls):

```jsonc
{
  "acls": [
    // Jason can only reach the n8n node on port 443
    {
      "action": "accept",
      "src": ["jason-device-name"],
      "dst": ["jlyve-n8n:443"]
    }
    // ... your other ACL rules
  ]
}
```

Replace `jason-device-name` with the name of Jason's device on your tailnet, and `jlyve-n8n` with your `TS_HOSTNAME`.

## Security Model

| Layer | Protection |
|-------|-----------|
| **Ingress** | Tailscale only — no ports published to host |
| **TLS** | Auto-provisioned HTTPS cert via Tailscale |
| **Auth** | n8n built-in authentication |
| **ACLs** | Tailscale restricts Jason to port 443 on the sidecar only |
| **n8n sandbox** | Read-only filesystem, all capabilities dropped, no-new-privileges, 2GB memory / 2 CPU limit |
| **Network isolation** | Ollama on internal-only network (no internet) |
| **GPU isolation** | Only Ollama has GPU access |

## Stopping and Restarting

```bash
docker compose down      # stop all services (data persists in volumes)
docker compose up -d     # restart
```

To fully reset (deletes all data):

```bash
docker compose down -v   # removes volumes too
```
