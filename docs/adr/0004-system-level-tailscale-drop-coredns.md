# System-level Tailscale, drop CoreDNS

Tailscale runs as a system-level package (apt) instead of a container. On Debian the kernel has full TUN/TAP support, so the `TS_USERSPACE=true` workaround for QNAP is no longer needed -- kernel-mode networking is faster and more reliable. CoreDNS is dropped entirely; Tailscale's built-in split DNS (configured in the Tailscale admin console) handles resolving `*.guidotto.dev` to the Tailscale IP when on the tailnet. One fewer service to manage.
