## Why

We need a secure, self-hosted environment where a friend (Jason) can build and experiment with n8n workflows using local GPU-accelerated AI models—without exposing the host machine or home network to the internet. The host has a 24GB VRAM NVIDIA GPU that should be available for LLM inference via Ollama, accessible through n8n's built-in AI agent nodes.

## What Changes

- Create a Docker Compose stack with three services: n8n, Ollama, and a Tailscale sidecar
- Pass the NVIDIA GPU through to the Ollama container for LLM inference
- Use Tailscale `serve` to provide Jason with an HTTPS URL to access n8n—no ports published to the host
- Isolate Ollama on an internal-only Docker network (no internet access)
- Sandbox the n8n container (read-only root, dropped capabilities, no-new-privileges, resource limits)
- Pre-pull `llama3.1:8b` model for immediate use
- Pre-configure n8n with Ollama credentials so AI agent nodes work out of the box
- Use named Docker volumes for persistent storage of n8n data and Ollama models

## Capabilities

### New Capabilities

- `docker-compose-stack`: Docker Compose configuration defining the three-service stack, networking, volumes, and GPU passthrough
- `tailscale-ingress`: Tailscale sidecar container configuration, `tailscale serve` setup, and ACL guidance for restricting Jason's access
- `n8n-sandbox`: Security hardening for the n8n container—filesystem, capabilities, resource limits, and network isolation
- `ollama-gpu`: Ollama service configuration with NVIDIA GPU passthrough, model pre-pulling, and network isolation on internal-only backend

### Modified Capabilities

_(none — greenfield project)_

## Impact

- **Dependencies**: Requires NVIDIA Container Toolkit installed on the host, Docker with Compose v2, and a Tailscale account with an auth key
- **Host system**: No ports published; GPU is shared with Ollama container; named Docker volumes created on host
- **Network**: Two Docker bridge networks created; Tailscale mesh connection established from sidecar
- **External services**: Tailscale account and ACL configuration needed; n8n workflows can reach external APIs
