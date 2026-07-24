# Cloudflare Firewall Lockdown

`allow_cf.sh` configures `iptables` and `ip6tables` so the user/Xray and panel ports accept new connections only from Cloudflare IP ranges. SSH remains reachable from any source, while other inbound traffic is dropped.

The script downloads the current Cloudflare IPv4 and IPv6 CIDRs from the Cloudflare API and validates the response before changing firewall rules.

## Requirements

- Linux system running Bash
- Root privileges
- `curl`
- `jq`
- `iptables`
- `ip6tables`
- Network access to `https://api.cloudflare.com/client/v4/ips`

The script uses Bash features including arrays, `mapfile`, `[[ ]]`, and strict mode. Run it with Bash rather than `sh`.

## Usage

From this directory:

```bash
sudo ./allow_cf.sh <user_port> <panel_port> [ssh_port] [--udp]
```

Examples:

```bash
# Protect TCP ports and use SSH port 22.
sudo ./allow_cf.sh 443 2053

# Protect TCP ports and use a custom SSH port.
sudo ./allow_cf.sh 443 2053 2222

# Protect both TCP and UDP on the two protected ports.
sudo ./allow_cf.sh 443 2053 --udp

# Use a custom SSH port and enable UDP protection.
sudo ./allow_cf.sh 443 2053 2222 --udp
```

### Arguments

| Argument | Description |
| --- | --- |
| `user_port` | Required port for the user/Xray service. New TCP connections are Cloudflare-only. |
| `panel_port` | Required port for the panel service. New TCP connections are Cloudflare-only. |
| `ssh_port` | Optional SSH TCP port, defaulting to `22`. New connections are allowed from all sources. |
| `--udp` | Also allow UDP from Cloudflare and reject non-Cloudflare UDP traffic on both protected ports. |
| `--help`, `-h` | Display usage information when supplied as an optional argument. |

All ports must be unique integers from `1` through `65535`. The two protected ports cannot equal the SSH port.

## Firewall Behavior

The script creates or rebuilds the private `CLOUDFLARE_LOCKDOWN` chain in both `iptables` and `ip6tables`, then inserts one jump from each `INPUT` chain to the managed chain. On each run, duplicate jumps to the managed chain are removed before the new jump is inserted.

For IPv4 and IPv6, the managed chain allows:

- Established and related connections
- Loopback traffic
- New TCP connections to the configured SSH port from any source
- ICMP or ICMPv6 traffic
- New TCP connections to both protected ports when the source is in Cloudflare's current CIDR lists
- With `--udp`, new UDP traffic to both protected ports when the source is in Cloudflare's current CIDR lists

The script then rejects non-Cloudflare traffic to protected ports and drops all other inbound traffic. TCP protected-port traffic is rejected with a TCP reset; UDP traffic is rejected with the appropriate ICMP port-unreachable response.

## Safety Notes

This script changes live firewall state and can disconnect you from the server.

1. Verify the SSH port before running it.
2. Keep the current SSH session open.
3. Test a second SSH connection before closing the first one.
4. Confirm that the configured user and panel services are reachable through Cloudflare.
5. Make sure the required IPv4 and IPv6 firewall commands are available before execution.

The script fetches and validates the Cloudflare response before changing firewall rules. If the download fails, the JSON is invalid, the API reports an error, or either address-family list is empty, the script exits without changing the firewall rules.

The script does not save or restore firewall rules. Configure a separate distribution-specific persistence mechanism if these rules must survive a reboot.

## Reapplying Configuration

Running the script again rebuilds only the `CLOUDFLARE_LOCKDOWN` chains managed by the script and inserts a fresh jump from each `INPUT` chain. It does not flush unrelated top-level firewall rules, but the final drop rule in the managed chain means unmatched inbound traffic is blocked before later `INPUT` rules are evaluated.

After a successful run, the script prints the resulting IPv4 and IPv6 managed chains with counters and line numbers.
