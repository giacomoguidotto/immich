# Drop Watchtower, GitOps with Renovate and ansible-pull

Watchtower is removed. Container image versions are pinned in compose files and updated via Renovate PRs. After merge, `ansible-pull` on a systemd timer (polling every few minutes) detects the change and applies the playbook. This gives controlled, auditable updates with a human review gate, matching the poll-based reconciliation pattern used by Flux and ArgoCD. Watchtower was rejected because it mutates running state outside of Ansible, causing drift between the repo and reality.
