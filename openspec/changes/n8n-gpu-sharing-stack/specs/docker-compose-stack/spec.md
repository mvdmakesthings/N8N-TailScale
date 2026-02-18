## ADDED Requirements

### Requirement: Compose file defines three services
The Docker Compose file SHALL define exactly three services: `n8n`, `ollama`, and `tailscale`.

#### Scenario: All services start successfully
- **WHEN** `docker compose up -d` is run on a host with NVIDIA Container Toolkit and Docker Compose v2 installed
- **THEN** all three services start without errors and reach a healthy state

### Requirement: Two isolated Docker networks
The Compose file SHALL define two bridge networks: `frontend` and `backend`. The `backend` network SHALL be configured with `internal: true` to prevent internet access.

#### Scenario: Network assignment
- **WHEN** the stack is running
- **THEN** `tailscale` is attached to `frontend` only, `n8n` is attached to both `frontend` and `backend`, and `ollama` is attached to `backend` only

#### Scenario: Backend network has no internet
- **WHEN** a process in the `ollama` container attempts to reach an external host
- **THEN** the connection is refused or times out because `backend` is internal-only

### Requirement: Named volumes for persistent storage
The Compose file SHALL define two named Docker volumes: `n8n_data` (mounted at `/home/node/.n8n` in the n8n container) and `ollama_data` (mounted at `/root/.ollama` in the ollama container).

#### Scenario: Data persists across restarts
- **WHEN** the stack is stopped with `docker compose down` and started again with `docker compose up -d`
- **THEN** n8n workflows, credentials, and execution history are preserved, and Ollama models remain available

### Requirement: No ports published to the host
The Compose file SHALL NOT publish any container ports to the host (no `ports:` directives). All ingress SHALL be handled exclusively through the Tailscale sidecar.

#### Scenario: No host port bindings
- **WHEN** the stack is running
- **THEN** `docker compose ps` shows no published ports and no service is reachable via `localhost`
