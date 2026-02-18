## ADDED Requirements

### Requirement: NVIDIA GPU passthrough
The Ollama container SHALL use the official `ollama/ollama` image and request access to all NVIDIA GPUs via Docker's `deploy.resources.reservations.devices` configuration with `driver: nvidia` and `count: all`.

#### Scenario: Ollama can use the GPU
- **WHEN** the Ollama container starts on a host with NVIDIA Container Toolkit installed
- **THEN** Ollama detects and uses the NVIDIA GPU for model inference

### Requirement: Ollama isolated on internal network
The Ollama container SHALL be attached only to the `backend` network (which is `internal: true`). It SHALL NOT be attached to any network with internet access.

#### Scenario: Ollama has no internet access
- **WHEN** a process in the Ollama container attempts an outbound internet connection
- **THEN** the connection fails because the backend network has no internet route

#### Scenario: n8n can reach Ollama
- **WHEN** n8n makes an HTTP request to `http://ollama:11434`
- **THEN** the request succeeds because both services share the `backend` network

### Requirement: Pre-pull llama3.1:8b model
The stack SHALL include a mechanism to pre-pull the `llama3.1:8b` model into the Ollama container so it is available immediately after first deployment.

#### Scenario: Model available on first start
- **WHEN** the stack is started for the first time and the model pull process completes
- **THEN** `llama3.1:8b` is available in Ollama's model list and ready for inference

### Requirement: Pre-configured Ollama credentials in n8n
The n8n container SHALL be configured with environment variables that set up Ollama as a default LLM provider, with the base URL `http://ollama:11434`, so that n8n's AI agent nodes can use Ollama without manual credential setup.

#### Scenario: AI agent node works without manual configuration
- **WHEN** Jason creates a new AI Agent workflow in n8n and selects the Ollama Chat Model node
- **THEN** the Ollama connection is pre-configured with the correct base URL and the `llama3.1:8b` model is available
