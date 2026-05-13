# Lightweight monitoring with Healthchecks.io, no on-node metrics stack

Monitoring uses Healthchecks.io (free tier, 20 checks) as a dead man's switch. Each systemd timer (backup, ansible-pull) pings a Healthchecks.io URL on success. Missing pings trigger alerts via email or push notification. No Prometheus, Grafana, or metrics agents run on the node -- the J1800 (2C/2T, 8 GB RAM) cannot spare the resources. A full observability stack (Prometheus + Grafana + node-exporter) is a future upgrade when hardware improves.
