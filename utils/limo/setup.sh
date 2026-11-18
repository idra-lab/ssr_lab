
#!/usr/bin/env bash

# ============================================================
# AGILEX LIMO - CYCLONEDDS NETWORK SETUP
# Run on the LIMO robot with:
#   source setup_limo.sh
# ============================================================

# Ensure the script is sourced
if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    echo "Error: run with 'source setup_limo.sh'"
    exit 1
fi

# ============================================================
# 1. IPv4 ADDRESS VALIDATION
# ============================================================

valid_ipv4() {
    local ip="$1"
    local part
    local -a octets

    [[ "$ip" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]] || return 1

    IFS='.' read -r -a octets <<< "$ip"

    for part in "${octets[@]}"; do
        [[ "$part" =~ ^[0-9]{1,3}$ ]] || return 1
        (( 10#$part <= 255 )) || return 1
    done
}

# ============================================================
# 2. REMOTE HOST IP ADDRESS (OPTIONAL)
# ============================================================

while true; do
    read -rp "Enter remote host PC IP address (Enter to skip): " HOST_IP

    if [[ -z "$HOST_IP" ]]; then
        echo "no ip added, ROS will only work inside LIMO"
        break
    fi

    if valid_ipv4 "$HOST_IP"; then
        break
    fi

    echo "Invalid IPv4 address. Example: 10.196.192.141"
done

# ============================================================
# 3. NETWORK INTERFACE
# ============================================================

# Always use the LIMO Wi-Fi interface
NETWORK_INTERFACE="wlan0"

if [[ ! -d "/sys/class/net/$NETWORK_INTERFACE" ]]; then
    echo "Error: network interface '$NETWORK_INTERFACE' not found."
    return 1
fi

echo "Selected network interface: $NETWORK_INTERFACE"

# ============================================================
# 4. AUTOMATIC LOCAL LIMO IP DETECTION
# ============================================================

# Get the IPv4 address assigned to wlan0
LIMO_IP=$(
    ip -4 -o addr show dev "$NETWORK_INTERFACE" scope global |
    awk '{
        split($4, address, "/")
        print address[1]
        exit
    }'
)

# Validate the detected IP address
if [[ -z "$LIMO_IP" ]] || ! valid_ipv4 "$LIMO_IP"; then
    echo "Error: no valid IPv4 address found on wlan0."
    echo "Check the Wi-Fi connection with:"
    echo "  ip -4 addr show wlan0"
    return 1
fi

echo "Detected local LIMO IP: $LIMO_IP"

# ============================================================
# 5. CYCLONEDDS XML PATH
# ============================================================

DEFAULT_XML="$HOME/cyclonedds.xml"

echo "Suggested CycloneDDS XML path: $DEFAULT_XML"

read -rp "Press Enter to accept, or enter another path: " XML_PATH

XML_PATH="${XML_PATH:-$DEFAULT_XML}"

# Expand home directory
if [[ "$XML_PATH" == "~/"* ]]; then
    XML_PATH="$HOME/${XML_PATH#\~/}"
fi

if [[ "$XML_PATH" != /* ]]; then
    echo "Error: XML path must be absolute."
    return 1
fi

mkdir -p "$(dirname "$XML_PATH")" || return 1

# ============================================================
# 6. BACKUP EXISTING CONFIGURATION
# ============================================================

if [[ -f "$XML_PATH" ]]; then
    echo "Existing configuration: $XML_PATH"
    read -rp "Overwrite existing XML? (y/N): " CONFIRM

    if [[ ! "$CONFIRM" =~ ^[Yy]$ ]]; then
        echo "Setup cancelled."
        return 1
    fi

    cp "$XML_PATH" "${XML_PATH}.bak" || return 1
    echo "Backup saved: ${XML_PATH}.bak"
fi

# ============================================================
# 7. GENERATE CYCLONEDDS XML
# ============================================================

# Add remote host peer only if an IP was provided
HOST_PEER=""

if [[ -n "$HOST_IP" ]]; then
    HOST_PEER="        <Peer Address=\"${HOST_IP}\"/>"
fi

cat > "$XML_PATH" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!-- CycloneDDS configuration for AgileX LIMO -->
<CycloneDDS xmlns="https://cdds.io/config">
  <Domain id="any">
    <General>
      <NetworkInterfaceAddress>${NETWORK_INTERFACE}</NetworkInterfaceAddress>
      <AllowMulticast>false</AllowMulticast>
    </General>

    <Discovery>
      <ParticipantIndex>auto</ParticipantIndex>
      <MaxAutoParticipantIndex>100</MaxAutoParticipantIndex>
      <Peers>
${HOST_PEER}
        <!-- Local LIMO -->
        <Peer Address="${LIMO_IP}"/>
      </Peers>
    </Discovery>
  </Domain>
</CycloneDDS>
EOF

if [[ $? -ne 0 ]]; then
    echo "Error: failed to write XML configuration."
    return 1
fi

# ============================================================
# 8. CONFIGURE ROS 2 ENVIRONMENT
# ============================================================

export RMW_IMPLEMENTATION=rmw_cyclonedds_cpp
export CYCLONEDDS_URI="file://${XML_PATH}"
export ROS_LOCALHOST_ONLY=0

# ============================================================
# 9. CONFIGURATION SUMMARY
# ============================================================

echo ""
echo "============================================"
echo " AGILEX LIMO - NETWORK SETUP COMPLETE"
echo "============================================"

if [[ -n "$HOST_IP" ]]; then
    echo "Remote host IP   : $HOST_IP"
else
    echo "Remote host IP   : not configured (LIMO only)"
fi

echo "Local LIMO IP    : $LIMO_IP"
echo "Network interface: $NETWORK_INTERFACE"
echo "ROS domain ID    : ${ROS_DOMAIN_ID:-not set}"
echo "DDS middleware   : $RMW_IMPLEMENTATION"
echo "CycloneDDS XML   : $XML_PATH"
echo "============================================"
echo ""

# ============================================================
# 8.1 RESTART ROS 2 DAEMON
# ============================================================

echo ""
echo "Restarting ROS 2 daemon..."

if command -v ros2 >/dev/null 2>&1; then
    ros2 daemon stop
    ros2 daemon start

    echo "ROS 2 daemon restart completed."
else
    echo "Warning: ROS 2 is not sourced."
    echo "Skipping daemon restart." 
fi
echo "Configuration applied to the current shell."
echo "Restart ROS 2 nodes to apply the new settings."

