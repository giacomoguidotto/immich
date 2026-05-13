# Separate config from persistent data on /data

The `/data` partition separates Ansible-managed config (`/data/services/`) from irreplaceable user data (`/data/storage/`). This creates a clean backup boundary: back up `/data/storage/`, ignore `/data/services/` since Ansible recreates it from the repo. The alternative -- co-locating config and data per service -- was rejected because it muddies the backup policy and makes it harder to distinguish what's reproducible from what's not.
