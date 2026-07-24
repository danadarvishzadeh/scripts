#!/usr/bin/env bash

set -euo pipefail

# Usage:
#   sudo ./allow_cf.sh <user_port> <panel_port> [ssh_port] [--udp]
#
# Examples:
#   sudo ./allow_cf.sh 443 2053
#   sudo ./allow_cf.sh 443 2053 22
#   sudo ./allow_cf.sh 443 2053 --udp
#   sudo ./allow_cf.sh 443 2053 22 --udp
#
# Behavior:
#   - Downloads current Cloudflare IPv4/IPv6 CIDRs from Cloudflare's API.
#   - User/Xray TCP port is accessible only from Cloudflare.
#   - Panel TCP port is accessible only from Cloudflare.
#   - With --udp, UDP on both protected ports is also Cloudflare-only.
#   - SSH TCP port is accessible from any source.
#   - Loopback, established connections, ICMP, and ICMPv6 are allowed.
#   - All other incoming traffic is dropped.
#
# Dependencies:
#   curl, jq, iptables, ip6tables
#
# WARNING:
#   Verify your SSH port before running this script.
#   Keep the current SSH connection open and test a second SSH connection.

readonly CHAIN_NAME="CLOUDFLARE_LOCKDOWN"
readonly CLOUDFLARE_IP_API="https://api.cloudflare.com/client/v4/ips"

die() {
    echo "Error: $*" >&2
    exit 1
}

usage() {
    cat <<EOF
Usage:
  sudo $0 <user_port> <panel_port> [ssh_port] [--udp]

Examples:
  sudo $0 443 2053
  sudo $0 443 2053 22
  sudo $0 443 2053 --udp
  sudo $0 443 2053 22 --udp
EOF
}

validate_port() {
    local port="$1"
    local label="$2"

    if ! [[ "$port" =~ ^[0-9]+$ ]]; then
        die "$label must be numeric."
    fi

    if ((10#$port < 1 || 10#$port > 65535)); then
        die "$label must be between 1 and 65535."
    fi
}

require_command() {
    local command_name="$1"

    command -v "$command_name" >/dev/null 2>&1 ||
        die "'$command_name' is required but is not installed."
}

print_command() {
    printf 'Executing:'
    printf ' %q' "$@"
    printf '\n'
}

run_command() {
    print_command "$@"
    "$@"
}

fetch_cloudflare_ranges() {
    local response_file
    local success
    local error_message

    response_file="$(mktemp)"
    trap 'rm -f "$response_file"' RETURN

    echo "Downloading Cloudflare IP ranges from:"
    echo "  $CLOUDFLARE_IP_API"

    if ! curl \
        --fail \
        --silent \
        --show-error \
        --location \
        --connect-timeout 10 \
        --max-time 30 \
        --retry 3 \
        --retry-delay 2 \
        --retry-connrefused \
        --output "$response_file" \
        "$CLOUDFLARE_IP_API"; then
        die "could not download Cloudflare IP ranges. Firewall rules were not changed."
    fi

    if ! jq empty "$response_file" >/dev/null 2>&1; then
        die "Cloudflare API returned invalid JSON. Firewall rules were not changed."
    fi

    success="$(jq -r '.success // false' "$response_file")"

    if [[ "$success" != "true" ]]; then
        error_message="$(
            jq -r '
                [.errors[]? | (.message // "Unknown API error")]
                | if length == 0 then "Unknown API error" else join("; ") end
            ' "$response_file"
        )"

        die "Cloudflare API request failed: $error_message"
    fi

    mapfile -t IPV4_RANGES < <(
        jq -r '.result.ipv4_cidrs[]? // empty' "$response_file"
    )

    mapfile -t IPV6_RANGES < <(
        jq -r '.result.ipv6_cidrs[]? // empty' "$response_file"
    )

    if ((${#IPV4_RANGES[@]} == 0)); then
        die "Cloudflare API returned no IPv4 CIDRs. Firewall rules were not changed."
    fi

    if ((${#IPV6_RANGES[@]} == 0)); then
        die "Cloudflare API returned no IPv6 CIDRs. Firewall rules were not changed."
    fi

    validate_cloudflare_ranges

    echo "Received ${#IPV4_RANGES[@]} IPv4 ranges."
    echo "Received ${#IPV6_RANGES[@]} IPv6 ranges."
}

validate_cloudflare_ranges() {
    local cidr

    # Basic defensive validation before passing API data to iptables.
    for cidr in "${IPV4_RANGES[@]}"; do
        if ! [[ "$cidr" =~ ^[0-9]{1,3}(\.[0-9]{1,3}){3}/([0-9]|[12][0-9]|3[0-2])$ ]]; then
            die "Cloudflare API returned an invalid IPv4 CIDR: $cidr"
        fi
    done

    for cidr in "${IPV6_RANGES[@]}"; do
        if ! [[ "$cidr" =~ ^[0-9A-Fa-f:]+/([0-9]|[1-9][0-9]|1[01][0-9]|12[0-8])$ ]]; then
            die "Cloudflare API returned an invalid IPv6 CIDR: $cidr"
        fi
    done
}

ensure_chain() {
    local firewall="$1"

    if "$firewall" -L "$CHAIN_NAME" -n >/dev/null 2>&1; then
        echo "Rebuilding existing $firewall chain: $CHAIN_NAME"

        # Only flush the private chain managed by this script.
        run_command "$firewall" -F "$CHAIN_NAME"
    else
        run_command "$firewall" -N "$CHAIN_NAME"
    fi
}

ensure_single_input_jump() {
    local firewall="$1"

    # Remove duplicate jumps created by older script versions.
    while "$firewall" -C INPUT -j "$CHAIN_NAME" 2>/dev/null; do
        run_command "$firewall" -D INPUT -j "$CHAIN_NAME"
    done

    # Insert the managed chain before other INPUT rules.
    run_command "$firewall" -I INPUT 1 -j "$CHAIN_NAME"
}

append_rule() {
    local firewall="$1"
    shift

    run_command "$firewall" -A "$CHAIN_NAME" "$@"
}

add_cloudflare_ipv4_rules() {
    local protocol="$1"
    local port="$2"
    local cidr

    for cidr in "${IPV4_RANGES[@]}"; do
        append_rule iptables \
            -p "$protocol" \
            -s "$cidr" \
            --dport "$port" \
            -m conntrack \
            --ctstate NEW \
            -j ACCEPT
    done
}

add_cloudflare_ipv6_rules() {
    local protocol="$1"
    local port="$2"
    local cidr

    for cidr in "${IPV6_RANGES[@]}"; do
        append_rule ip6tables \
            -p "$protocol" \
            -s "$cidr" \
            --dport "$port" \
            -m conntrack \
            --ctstate NEW \
            -j ACCEPT
    done
}

add_ipv4_protected_port() {
    local port="$1"

    add_cloudflare_ipv4_rules tcp "$port"

    # Reject TCP connections to this port from non-Cloudflare sources.
    append_rule iptables \
        -p tcp \
        --dport "$port" \
        -j REJECT \
        --reject-with tcp-reset

    if [[ "$ENABLE_UDP" == "true" ]]; then
        add_cloudflare_ipv4_rules udp "$port"

        # Reject UDP packets to this port from non-Cloudflare sources.
        append_rule iptables \
            -p udp \
            --dport "$port" \
            -j REJECT \
            --reject-with icmp-port-unreachable
    fi
}

add_ipv6_protected_port() {
    local port="$1"

    add_cloudflare_ipv6_rules tcp "$port"

    # Reject TCP connections to this port from non-Cloudflare sources.
    append_rule ip6tables \
        -p tcp \
        --dport "$port" \
        -j REJECT \
        --reject-with tcp-reset

    if [[ "$ENABLE_UDP" == "true" ]]; then
        add_cloudflare_ipv6_rules udp "$port"

        # Reject UDP packets to this port from non-Cloudflare sources.
        append_rule ip6tables \
            -p udp \
            --dport "$port" \
            -j REJECT \
            --reject-with icmp6-port-unreachable
    fi
}

configure_ipv4() {
    echo
    echo "Configuring IPv4 rules..."

    ensure_chain iptables
    ensure_single_input_jump iptables

    append_rule iptables \
        -m conntrack \
        --ctstate ESTABLISHED,RELATED \
        -j ACCEPT

    append_rule iptables \
        -i lo \
        -j ACCEPT

    # SSH remains globally accessible over TCP.
    append_rule iptables \
        -p tcp \
        --dport "$SSH_PORT" \
        -m conntrack \
        --ctstate NEW \
        -j ACCEPT

    # Keep IPv4 diagnostics and required ICMP behavior working.
    append_rule iptables \
        -p icmp \
        -j ACCEPT

    add_ipv4_protected_port "$USER_PORT"
    add_ipv4_protected_port "$PANEL_PORT"

    # Drop all remaining inbound IPv4 traffic.
    append_rule iptables -j DROP
}

configure_ipv6() {
    echo
    echo "Configuring IPv6 rules..."

    ensure_chain ip6tables
    ensure_single_input_jump ip6tables

    append_rule ip6tables \
        -m conntrack \
        --ctstate ESTABLISHED,RELATED \
        -j ACCEPT

    append_rule ip6tables \
        -i lo \
        -j ACCEPT

    # SSH remains globally accessible over TCP.
    append_rule ip6tables \
        -p tcp \
        --dport "$SSH_PORT" \
        -m conntrack \
        --ctstate NEW \
        -j ACCEPT

    # ICMPv6 is required for normal IPv6 operation.
    append_rule ip6tables \
        -p ipv6-icmp \
        -j ACCEPT

    add_ipv6_protected_port "$USER_PORT"
    add_ipv6_protected_port "$PANEL_PORT"

    # Drop all remaining inbound IPv6 traffic.
    append_rule ip6tables -j DROP
}

parse_arguments() {
    if (($# < 2 || $# > 4)); then
        usage
        exit 1
    fi

    USER_PORT="$1"
    PANEL_PORT="$2"
    SSH_PORT="22"
    ENABLE_UDP="false"

    shift 2

    local ssh_port_supplied="false"
    local argument

    for argument in "$@"; do
        case "$argument" in
            --udp)
                if [[ "$ENABLE_UDP" == "true" ]]; then
                    die "--udp was supplied more than once."
                fi

                ENABLE_UDP="true"
                ;;

            --help|-h)
                usage
                exit 0
                ;;

            *)
                if [[ "$argument" =~ ^[0-9]+$ ]] &&
                    [[ "$ssh_port_supplied" == "false" ]]; then
                    SSH_PORT="$argument"
                    ssh_port_supplied="true"
                else
                    die "unknown or duplicate argument: $argument"
                fi
                ;;
        esac
    done

    validate_port "$USER_PORT" "User port"
    validate_port "$PANEL_PORT" "Panel port"
    validate_port "$SSH_PORT" "SSH port"

    if [[ "$USER_PORT" == "$PANEL_PORT" ]]; then
        die "user port and panel port must be different."
    fi

    if [[ "$USER_PORT" == "$SSH_PORT" ]]; then
        die "user port and SSH port must be different."
    fi

    if [[ "$PANEL_PORT" == "$SSH_PORT" ]]; then
        die "panel port and SSH port must be different."
    fi

    readonly USER_PORT
    readonly PANEL_PORT
    readonly SSH_PORT
    readonly ENABLE_UDP
}

main() {
    if [[ $EUID -ne 0 ]]; then
        die "this script must be run as root."
    fi

    parse_arguments "$@"

    require_command curl
    require_command jq
    require_command iptables
    require_command ip6tables

    # These arrays are populated from the Cloudflare API.
    declare -g -a IPV4_RANGES=()
    declare -g -a IPV6_RANGES=()

    # Fetch and validate all CIDRs before changing firewall rules.
    fetch_cloudflare_ranges

    echo
    echo "Firewall configuration:"
    echo "  User/Xray port : $USER_PORT — Cloudflare only"
    echo "  Panel port     : $PANEL_PORT — Cloudflare only"
    echo "  SSH port       : $SSH_PORT — TCP from all sources"

    if [[ "$ENABLE_UDP" == "true" ]]; then
        echo "  Protected ports: TCP and UDP"
    else
        echo "  Protected ports: TCP only"
    fi

    echo "  Other inbound ports: blocked"

    configure_ipv4
    configure_ipv6

    echo
    echo "Firewall configuration completed successfully."

    echo
    echo "IPv4 rules:"
    iptables -L "$CHAIN_NAME" -n -v --line-numbers

    echo
    echo "IPv6 rules:"
    ip6tables -L "$CHAIN_NAME" -n -v --line-numbers

    echo
    echo "Test SSH in another terminal before closing this connection."
    echo "Persist these rules separately if they must survive a reboot."
}

main "$@"