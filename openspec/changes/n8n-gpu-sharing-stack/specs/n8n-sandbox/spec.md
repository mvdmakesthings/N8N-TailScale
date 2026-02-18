## ADDED Requirements

### Requirement: Read-only root filesystem
The n8n container SHALL run with a read-only root filesystem (`read_only: true`). A `tmpfs` mount SHALL be provided at `/tmp` for ephemeral scratch space.

#### Scenario: Container filesystem is immutable
- **WHEN** a process inside the n8n container attempts to write to a path outside `/tmp` and the mounted data volume
- **THEN** the write fails with a read-only filesystem error

### Requirement: Dropped capabilities and no privilege escalation
The n8n container SHALL drop all Linux capabilities (`cap_drop: [ALL]`) and set `security_opt: [no-new-privileges:true]`.

#### Scenario: Privilege escalation blocked
- **WHEN** a process inside the n8n container attempts to gain additional privileges (e.g., via setuid binaries)
- **THEN** the operation is denied

### Requirement: Resource limits
The n8n container SHALL have memory and CPU limits configured to prevent runaway workflows from exhausting host resources.

#### Scenario: Runaway workflow is constrained
- **WHEN** an n8n workflow or Code node attempts to consume unbounded memory
- **THEN** the container is killed by the OOM killer when it exceeds its memory limit

### Requirement: No GPU access for n8n
The n8n container SHALL NOT have access to the NVIDIA GPU. GPU resources SHALL be reserved exclusively for the Ollama container.

#### Scenario: n8n cannot use GPU
- **WHEN** a Code node in n8n attempts to access GPU resources
- **THEN** no GPU device is visible inside the n8n container

### Requirement: n8n webhook URL configured for Tailscale
The n8n container SHALL set `WEBHOOK_URL` to the Tailscale HTTPS hostname so that generated webhook URLs are routable through the tailnet.

#### Scenario: Webhook URLs use Tailscale hostname
- **WHEN** a workflow creates a webhook trigger
- **THEN** the displayed webhook URL uses the `https://<node-name>.<tailnet>.ts.net` hostname
