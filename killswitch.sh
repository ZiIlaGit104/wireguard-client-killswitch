#!/usr/bin/with-contenv bash

echo "[KILLSWITCH] Initializing Dynamic Killswitch..."

# === 1. IPv6 HARD BLOCK ===
ip6tables -F
ip6tables -P INPUT DROP
ip6tables -P OUTPUT DROP
ip6tables -P FORWARD DROP

# === 2. DYNAMIC PARSING ===
CONFIG_PATH=$(find /config/wg_confs -maxdepth 1 -type f -name "*.conf" | head -n1)

if [ -z "$CONFIG_PATH" ]; then
    echo "[KILLSWITCH] ERROR: No configuration file found in /config/wg_confs. Exit."
    exit 1
fi

# Parse Endpoint Host and Port
# Handles formats like "Endpoint = 216.131.80.75:51820" or "Endpoint = vpn.provider.com:51820"
ENDPOINT_FULL=$(grep -i '^Endpoint' "$CONFIG_PATH" | awk -F '= ' '{print $2}')
ENDPOINT_HOST=$(echo "$ENDPOINT_FULL" | cut -d: -f1)
ENDPOINT_PORT=$(echo "$ENDPOINT_FULL" | cut -d: -f2)
[ -z "$ENDPOINT_PORT" ] && ENDPOINT_PORT=51820 # Default if port is missing

# Resolve Endpoint IP (in case it's a hostname)
ENDPOINT_IP=$(getent hosts "$ENDPOINT_HOST" | awk '{ print $1; exit }')

# Parse DNS Servers (handles comma-separated lists)
DNS_SERVERS=$(grep -i '^DNS' "$CONFIG_PATH" | awk -F '= ' '{print $2}' | tr -d ' ')

echo "[KILLSWITCH] Detected Endpoint: $ENDPOINT_IP on Port: $ENDPOINT_PORT"
echo "[KILLSWITCH] Detected DNS Servers: $DNS_SERVERS"

# === 3. IPTABLES RESET ===
iptables -F OUTPUT
iptables -P OUTPUT DROP

# === 4. ALLOW RULES ===
iptables -A OUTPUT -o lo -j ACCEPT
iptables -A OUTPUT -d "$ENDPOINT_IP" -p udp --dport "$ENDPOINT_PORT" -j ACCEPT
iptables -A OUTPUT -o wg+ -j ACCEPT

# STRICT DNS: Whitelist only the DNS servers from the config
echo "[KILLSWITCH] Whitelisting DNS: $DNS_SERVERS"
OLD_IFS=$IFS
IFS=','
for dns in $DNS_SERVERS; do
    if [ -n "$dns" ]; then
        iptables -A OUTPUT -d "$dns" -p udp --dport 53 -j ACCEPT
        iptables -A OUTPUT -d "$dns" -p tcp --dport 53 -j ACCEPT
    fi
done
IFS=$OLD_IFS

# === 5. LAN ACCESS (WITH DNS KILL) ===

# A. Block all OTHER DNS queries to the LAN ranges
# This catches your local router/DNS server before the general allow rules
for subnet in 10.0.0.0/8 172.16.0.0/12 192.168.0.0/16; do
    iptables -A OUTPUT -d "$subnet" -p udp --dport 53 -j REJECT
    iptables -A OUTPUT -d "$subnet" -p tcp --dport 53 -j REJECT
done

# B. Allow all other non-DNS traffic to the LAN
iptables -A OUTPUT -d 10.0.0.0/8 -j ACCEPT
iptables -A OUTPUT -d 172.16.0.0/12 -j ACCEPT
iptables -A OUTPUT -d 192.168.0.0/16 -j ACCEPT

# === 6. FINAL CATCH-ALL REJECT ===
iptables -A OUTPUT -j REJECT --reject-with icmp-port-unreachable

echo "[KILLSWITCH] Dynamic rules applied successfully."
