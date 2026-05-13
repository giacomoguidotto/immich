# Homelab

A personal self-hosted infrastructure running on a single physical NAS, managed declaratively with Ansible. Designed to host multiple services with security as the primary concern and high availability as secondary.

## Language

**Homelab**:
The complete self-hosted infrastructure: hardware, OS, networking, and all services running on it.
_Avoid_: NAS, server, cluster

**Node**:
A physical or virtual machine managed by Ansible. Named with the pattern `infra-node<NN>` (e.g. `infra-node01`).
_Avoid_: Host, server, box, ops01

**Service**:
A user-facing application running as one or more containers (e.g. Immich, Nextcloud, a status page). Each **Service** gets its own subdomain under `guidotto.dev` and has its own Docker Compose file managed by a dedicated Ansible role.
_Avoid_: App, stack, workload

**Infra**:
The project/repo name. Contains all Ansible playbooks, roles, preseed config, OpenTofu modules, and documentation to reproduce the **Homelab** from scratch. Prefers open-source dependencies throughout.
_Avoid_: immich-config, home-ops

### Infrastructure layer

These run as system-level services (apt packages, systemd), not containers. They are shared by all **Services**.

**Caddy**:
System-level reverse proxy and TLS terminator. Routes `<service>.guidotto.dev` subdomains to container ports. Single Caddyfile with per-service site configs dropped by each Ansible role.
_Avoid_: Nginx, Traefik

**Tailscale**:
System-level VPN mesh providing private access to the **Homelab**. Runs in kernel mode on Debian (no userspace workaround). Handles split DNS for `*.guidotto.dev` via the Tailscale admin console. Also the only SSH access path -- SSH is not exposed on the public network.
_Avoid_: WireGuard (raw), OpenVPN

**cloudflared**:
System-level Cloudflare Tunnel connector providing public ingress. Routes public traffic to Caddy on localhost. No inbound ports exposed.
_Avoid_: Reverse tunnel, port forwarding

**OpenTofu**:
Open-source infrastructure-as-code tool managing cloud resources (Cloudflare DNS records, tunnel config). Runs from the operator's machine, not on the **Node**.
_Avoid_: Terraform (proprietary)

### Access model

- **SSH**: Tailscale-only. Key-based auth via 1Password SSH agent. `root` login disabled. Single user `infra` with sudo.
- **Firewall**: `ufw` default deny inbound, allow 443 only. SSH reachable only on the Tailscale interface.
- **Secrets**: Ansible Vault. One vault password to rebuild everything from zero.

### Update model

- Container image versions pinned in compose files (no `:latest` tags)
- **Renovate** opens PRs for version bumps
- Human reviews and merges
- **`ansible-pull`** on a systemd timer polls the repo and applies changes automatically
- **`unattended-upgrades`** applies Debian security patches automatically
- Git log is the full audit trail

### Isolation model

- Each **Service** runs in its own Docker network (no cross-service container communication)
- **Caddy** reaches services via published ports on localhost, not Docker networks
- Journald and Docker log rotation enforce local disk limits
- Future: OpenTelemetry collector (Axiom) for centralized log management

### Ingress paths

Two paths reach a **Service**:

- **Public**: Internet → Cloudflare Edge → cloudflared → Caddy → container port
- **Private**: Tailscale client → split DNS → Caddy → container port

## Relationships

- A **Homelab** contains one or more **Nodes**
- A **Node** hosts one or more **Services**
- Each **Service** is independently deployable via its own Ansible role and Docker Compose file
- Each **Service** is reachable at `<service>.guidotto.dev`
- **Caddy**, **Tailscale**, and **cloudflared** are shared infrastructure, not **Services**
- **Renovate** proposes updates, **`ansible-pull`** applies them after merge

## Example dialogue

> **Dev:** "When I add a new **Service** to the **Homelab**, what do I need to touch?"
> **Domain expert:** "Create an Ansible role that templates a Docker Compose file into `/data/services/<name>/`, drops a Caddy site config into `/etc/caddy/sites/`, and adds a Cloudflare tunnel ingress rule. Re-run the playbook and the **Service** is live at `<name>.guidotto.dev`."

> **Dev:** "What if `infra-node01` dies completely?"
> **Domain expert:** "Flash a Debian preseed USB, boot, run `ansible-playbook site.yml`. Data survives on the RAID 1 `/data` partition. The **Infra** repo has everything needed to rebuild."

> **Dev:** "How do updates get deployed?"
> **Domain expert:** "Renovate opens a PR to bump the image version. You merge it. `ansible-pull` on `infra-node01` picks up the change within minutes and applies it."

## Flagged ambiguities

- "immich-config" was the original repo name scoped to a single service -- resolved: the project is called **Infra**, the repo will be renamed.
- "nicagi-store01" was the QNAP hostname -- resolved: the machine is **infra-node01** under the new naming convention.
- "nicagiMaster" was the QNAP admin user -- resolved: the user is **infra**, a non-root account with sudo.
- "CoreDNS" was used for split DNS -- resolved: dropped in favor of Tailscale's built-in split DNS. One fewer component.
- "ops01.guidotto.dev" was proposed as a machine domain -- resolved: the machine has no public domain. It's accessed via Tailscale hostname only. Only **Services** get subdomains.
- "Watchtower" was used for auto-updates -- resolved: dropped in favor of Renovate PRs + `ansible-pull` polling. The repo is the source of truth, not the running state.
