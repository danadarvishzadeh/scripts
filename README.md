# Linux Server Administration Scripts

This repository contains Bash scripts for configuring Linux servers. The current feature configures a Cloudflare-restricted firewall for a user/Xray service and its panel.

## Available Scripts

### Cloudflare Firewall Lockdown

[`allow_cf/allow_cf.sh`](allow_cf/allow_cf.sh) configures both `iptables` and `ip6tables` so two protected ports accept new connections only from Cloudflare IP ranges. SSH remains accessible from all sources, and other inbound traffic is dropped.

See the [Cloudflare firewall README](allow_cf/README.md) for prerequisites, usage examples, firewall behavior, and safety warnings.

## Requirements

- Linux with Bash
- Root privileges for scripts that modify system state
- Dependencies listed in each script's README

Run Bash scripts with `bash` or their executable path. Do not run them with `sh` when they use Bash-specific features such as arrays, `mapfile`, `[[ ]]`, or `set -euo pipefail`.

## Operational Safety

Read the feature-specific documentation before running a script against a production server. Scripts in this repository may change live firewall or other system state. Keep an existing administrative session open, verify the relevant access port, and test a second connection before closing the first.

Do not assume that system changes persist across reboot. Check the relevant feature documentation for persistence behavior and configure a separate persistence mechanism when required.

## Repository Layout

```text
allow_cf/
	allow_cf.sh      Cloudflare-only firewall configuration
	README.md        Feature usage and operational documentation
```
