## 1. Project Scaffolding

- [x] 1.1 Create `.env.example` with all required environment variables (`TS_AUTHKEY`, `TS_HOSTNAME`, `N8N_ENCRYPTION_KEY`, `N8N_USER_MANAGEMENT_JWT_SECRET`, `WEBHOOK_URL`)
- [x] 1.2 Create `.gitignore` excluding `.env`, Docker volume data, and OS files
- [x] 1.3 Create `tailscale/serve-config.json` with the Tailscale serve HTTPS→n8n proxy configuration

## 2. Docker Compose File

- [x] 2.1 Create `docker-compose.yml` with the two networks: `frontend` (bridge) and `backend` (bridge, `internal: true`)
- [x] 2.2 Define named volumes `n8n_data` and `ollama_data`
- [x] 2.3 Add the `tailscale` service using `tailscale/tailscale` image with `NET_ADMIN`/`SYS_MODULE` caps, `/dev/net/tun`, env vars from `.env`, and the serve config volume mount. Attach to `frontend` only.
- [x] 2.4 Add the `ollama` service using `ollama/ollama` image with NVIDIA GPU reservation (`deploy.resources.reservations.devices`), `ollama_data` volume, and attach to `backend` only
- [x] 2.5 Add the `n8n` service using `n8nio/n8n` image with sandbox settings (`read_only`, `tmpfs`, `cap_drop: [ALL]`, `no-new-privileges`, memory/cpu limits), `n8n_data` volume, Ollama base URL env var, and webhook URL. Attach to both `frontend` and `backend`. Set `depends_on` for tailscale and ollama.
- [x] 2.6 Verify no `ports:` directives exist on any service

## 3. Model Pre-Pull

- [x] 3.1 Add an `ollama-init` service that uses the `ollama/ollama` image, shares the `ollama_data` volume, attaches to `frontend` (for internet access), and runs `ollama pull llama3.1:8b` then exits
- [x] 3.2 Configure `ollama` service to `depend_on` `ollama-init` completing successfully (with `condition: service_completed_successfully`)

## 4. Documentation

- [x] 4.1 Create a README with prerequisites (NVIDIA Container Toolkit, Docker Compose v2, Tailscale account), setup instructions (copy `.env.example` to `.env`, fill in values, `docker compose up -d`), and Tailscale ACL configuration guidance
- [x] 4.2 Document how Jason can pull additional models (via n8n HTTP Request node or `docker compose exec ollama ollama pull <model>`)
