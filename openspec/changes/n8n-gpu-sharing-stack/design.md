## Context

This is a greenfield project. The host machine runs Linux (WSL2) with an NVIDIA GPU (24GB VRAM) and has Docker with Compose v2 and NVIDIA Container Toolkit installed. There is no existing infrastructure — we're building from scratch.

The goal is a single `docker compose up -d` that gives a friend (Jason) a secure, GPU-accelerated n8n environment accessible via a Tailscale HTTPS URL.

## Goals / Non-Goals

**Goals:**
- One-command deployment (`docker compose up -d`)
- Jason accesses n8n via a Tailscale HTTPS URL with zero port exposure on the host
- Ollama serves LLM inference on the NVIDIA GPU, reachable only from n8n
- n8n is sandboxed to prevent container escape or host access
- Persistent storage survives container restarts
- Pre-pulled model and pre-configured credentials for immediate productivity

**Non-Goals:**
- Multi-user access control beyond n8n's built-in auth
- Automated model management or a model marketplace
- Monitoring, logging, or alerting infrastructure
- CI/CD pipeline for the stack
- Support for AMD/Intel GPUs
- Running on a cloud provider — this is home-network-only

## Decisions

### 1. Docker Compose with two bridge networks

**Decision**: Use two Docker bridge networks — `frontend` (default bridge with internet) and `backend` (bridge with `internal: true`).

**Rationale**: n8n needs internet access for external API calls in workflows. Ollama does not — models are pre-pulled and inference is local. Putting Ollama on an internal-only network eliminates it as a pivot point for data exfiltration. n8n bridges both networks.

**Alternatives considered**:
- Single network with firewall rules: More complex, harder to reason about, Docker's `internal` flag is purpose-built for this.
- `--net=host`: Destroys all network isolation. Rejected.

### 2. Tailscale sidecar container with `tailscale serve`

**Decision**: Run Tailscale in its own container using the official `tailscale/tailscale` image. Use `tailscale serve --https=443 http://n8n:5678` for HTTPS reverse proxy.

**Rationale**: The sidecar pattern keeps Tailscale's elevated privileges (`NET_ADMIN`, `/dev/net/tun`) isolated from the n8n and Ollama containers. `tailscale serve` auto-provisions TLS certificates and provides a clean `https://<hostname>.ts.net` URL.

**Alternatives considered**:
- Tailscale on the host: Exposes the entire host to the tailnet. Rejected for security.
- Tailscale inside the n8n container: Requires a custom image and mixes concerns. Harder to update independently.
- Tailscale Funnel: Creates a public URL — explicitly unwanted.

### 3. Tailscale serve config via JSON file

**Decision**: Use a `TS_SERVE_CONFIG` JSON file mounted into the Tailscale container rather than running `tailscale serve` as a command after startup.

**Rationale**: Declarative configuration is more reliable than imperative commands that depend on timing. The JSON config is applied at startup and doesn't require waiting for the Tailscale daemon to be ready.

### 4. n8n sandbox via Docker security primitives

**Decision**: Harden the n8n container with `read_only: true`, `tmpfs` on `/tmp`, `cap_drop: [ALL]`, `no-new-privileges`, and memory/CPU limits.

**Rationale**: n8n's Code node executes arbitrary JavaScript. While n8n has its own sandboxing (isolated-vm), defense-in-depth at the container level prevents escape even if n8n's sandbox has vulnerabilities. The read-only filesystem prevents persistent tampering.

**Alternatives considered**:
- gVisor/Kata containers: Stronger isolation but significantly more complex to set up and may conflict with GPU passthrough.
- Disabling Code node entirely: Too restrictive — Code nodes are valuable for workflows.

### 5. Model pre-pull via init container pattern

**Decision**: Use a `depends_on` + healthcheck pattern where a one-shot init service pulls `llama3.1:8b` into the Ollama volume before n8n starts, or use an entrypoint wrapper script that pulls the model on first boot.

**Rationale**: Ollama is on the `backend` (internal-only) network, so it cannot pull models from the internet at runtime. Models must be pulled before the network isolation takes effect, or via a sidecar that has internet access.

**Revised approach**: Attach Ollama to `frontend` temporarily during the init phase, OR use a separate `ollama-init` service on `frontend` that pulls the model into the shared `ollama_data` volume and then exits. The main `ollama` service stays on `backend` only.

### 6. Secrets via `.env` file

**Decision**: Store `TS_AUTHKEY`, `TS_HOSTNAME`, and n8n encryption keys in a `.env` file, excluded from version control via `.gitignore`. Provide a `.env.example` as a template.

**Rationale**: Standard Docker Compose pattern. No need for a secrets manager for a home-lab setup.

## Risks / Trade-offs

- **[n8n Code node can reach the internet]** → n8n must have internet access for workflows, which means Code nodes can also make outbound requests. Mitigation: this is acceptable given the trust level with Jason; container-level isolation prevents host access.
- **[Tailscale auth key expiry]** → Auth keys expire. Mitigation: Use a reusable auth key or document how to rotate.
- **[24GB VRAM contention]** → If multiple large models are loaded, Ollama may OOM. Mitigation: Start with `llama3.1:8b` (5GB) which leaves ample headroom. Document model size guidance.
- **[WSL2 GPU passthrough]** → NVIDIA GPU passthrough in WSL2 + Docker requires specific driver versions. Mitigation: Document prerequisites and version requirements.
- **[Model pull requires internet for Ollama]** → Ollama's `backend` network is internal-only, so model pulling needs a workaround. Mitigation: Use an init service or manual pre-pull step.

## Open Questions

- What memory and CPU limits are appropriate for the n8n container on this host? (Depends on total host resources beyond GPU.)
- Should we include a healthcheck-based dependency chain so n8n waits for Ollama to be ready before starting?
