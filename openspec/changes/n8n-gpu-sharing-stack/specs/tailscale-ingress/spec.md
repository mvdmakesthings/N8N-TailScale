## ADDED Requirements

### Requirement: Tailscale sidecar joins the tailnet
The `tailscale` service SHALL use the official `tailscale/tailscale` image and authenticate to the tailnet using a `TS_AUTHKEY` environment variable. It SHALL be granted `NET_ADMIN` and `SYS_MODULE` capabilities and access to `/dev/net/tun`.

#### Scenario: Sidecar authenticates and appears on tailnet
- **WHEN** the stack starts with a valid `TS_AUTHKEY`
- **THEN** the sidecar registers as a node on the tailnet and is reachable by other tailnet devices

### Requirement: HTTPS reverse proxy to n8n via tailscale serve
The sidecar SHALL run `tailscale serve` to reverse-proxy HTTPS traffic on port 443 to `http://n8n:5678`. Tailscale SHALL auto-provision a TLS certificate for the node's tailnet hostname.

#### Scenario: Jason accesses n8n via HTTPS URL
- **WHEN** Jason navigates to `https://<node-name>.<tailnet>.ts.net` from a device on the tailnet
- **THEN** he receives the n8n login page over a valid HTTPS connection

### Requirement: Tailscale ACL guidance
The project SHALL include documentation describing the recommended Tailscale ACL configuration that restricts Jason's device to only reach the sidecar node on port 443.

#### Scenario: Jason cannot reach other tailnet devices
- **WHEN** Jason's device attempts to connect to any tailnet node other than the sidecar, or to any port other than 443 on the sidecar
- **THEN** the connection is denied by Tailscale ACL policy

### Requirement: Auth key provided via environment file
The `TS_AUTHKEY` and `TS_HOSTNAME` values SHALL be read from a `.env` file that is listed in `.gitignore`. The project SHALL include a `.env.example` file documenting the required variables.

#### Scenario: Secrets not committed to version control
- **WHEN** the repository is committed
- **THEN** the `.env` file is excluded by `.gitignore` and only `.env.example` is tracked
