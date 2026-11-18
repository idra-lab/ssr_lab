
#!/usr/bin/env bash

# ============================================================
# ROS 2 LIMO - CROSS-PLATFORM NETWORK SETUP
#
# Supported systems:
#   - Linux (Ubuntu)
#   - macOS
#
# Usage:
#   source setup.sh
#
# Features:
# - Detect operating system
# - Find or load ROS 2 environment
# - Select LIMO robot (1-12)
# - Ask for remote LIMO IP
# - Detect local network interface and IP
# - Configure CycloneDDS unicast peers
# - Generate XML with backup
# - Export ROS 2 environment variables
# ============================================================

# Ensure the script is sourced
if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    echo "Error: run with 'source setup.sh'"
    exit 1
fi

# ============================================================
# 1. DETECT OPERATING SYSTEM
# ============================================================

OS=$(uname -s)

case "$OS" in
    Linux)
        echo "Operating system: Linux"
        ;;
    Darwin)
        echo "Operating system: macOS"
        ;;
    *)
        echo "Error: unsupported operating system: $OS"
        return 1
        ;;
esac

# ============================================================
# 2. ROS 2 ENVIRONMENT
# ============================================================

# Use the already loaded ROS 2 environment if available
if [[ -n "${ROS_DISTRO:-}" ]] && command -v ros2 >/dev/null 2>&1; then
    echo "ROS 2 already loaded: $ROS_DISTRO"

else
    ROS_SETUP=""

    # Standard Linux ROS 2 installation
    if [[ "$OS" == "Linux" && -d /opt/ros ]]; then
        ROS_SETUP=$(
            find /opt/ros -mindepth 2 -maxdepth 2 \
                -name setup.bash 2>/dev/null |
            sort -V |
            tail -n 1
        )
    fi

    # Check common macOS / source installation paths
    if [[ -z "$ROS_SETUP" ]]; then
        for candidate in \
            "$HOME/ros2_ws/install/setup.bash" \
            "$HOME/ros2/install/setup.bash" \
            "$HOME/ros2_rolling/install/setup.bash" \
            "$HOME/ros2_humble/install/setup.bash" \
            "$HOME/ros2_jazzy/install/setup.bash"
        do
            if [[ -f "$candidate" ]]; then
                ROS_SETUP="$candidate"
                break
            fi
        done
    fi

    # Ask for custom ROS 2 setup path if not found
    if [[ -z "$ROS_SETUP" ]]; then
        echo ""
        echo "ROS 2 installation not found automatically."
        read -rp "Enter ROS 2 setup.bash path: " ROS_SETUP

        if [[ "$ROS_SETUP" == "~/"* ]]; then
            ROS_SETUP="$HOME/${ROS_SETUP#\~/}"
        fi
    fi

    if [[ ! -f "$ROS_SETUP" ]]; then
        echo "Error: ROS 2 setup.bash not found: $ROS_SETUP"
        return 1
    fi

    source "$ROS_SETUP" || return 1

    echo "ROS 2 environment loaded: ${ROS_DISTRO:-unknown}"
fi

# ============================================================
# 3. IPv4 ADDRESS VALIDATION
# ============================================================


valid_ipv4() {
    local ip="$1"
    local part
    local -a octets

    # Check IPv4 format
    [[ "$ip" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]] || return 1

    # Split IP address into octets
    IFS='.' read -r -a octets <<< "$ip"

    # Validate each octet (0-255)
    for part in "${octets[@]}"; do
        [[ "$part" =~ ^[0-9]{1,3}$ ]] || return 1
        (( 10#$part <= 255 )) || return 1
    done

    return 0
}

# ============================================================
# 4. SELECT LIMO ROBOT
# ============================================================

while true; do
    read -rp "Which LIMO robot are you using? (1-13): " LIMO_NUMBER

    if [[ "$LIMO_NUMBER" =~ ^([1-9]|1[0-3])$ ]]; then
        break
    fi

    echo "Invalid selection. Enter a number between 1 and 12."
done

export LIMO_NAMESPACE="limo_${LIMO_NUMBER}"
export ROS_DOMAIN_ID="$LIMO_NUMBER"
export ROS_LOCALHOST_ONLY=0

# ============================================================
# 5. REMOTE LIMO IP ADDRESS
# ============================================================

while true; do
    read -rp "Enter LIMO ${LIMO_NUMBER} IP address: " LIMO_IP

    if valid_ipv4 "$LIMO_IP"; then
        break
    fi

    echo "Invalid IPv4 address. Example: 10.196.210.197"
done

# ============================================================
# 6. DETECT NETWORK INTERFACE AND LOCAL IP
# ============================================================

NETWORK_INTERFACE=""
HOST_IP=""

if [[ "$OS" == "Linux" ]]; then

    # Linux: detect route to the LIMO
    ROUTE_INFO=$(ip -4 route get "$LIMO_IP" 2>/dev/null)

    NETWORK_INTERFACE=$(
        printf '%s\n' "$ROUTE_INFO" |
        awk '{
            for (i = 1; i <= NF; i++)
                if ($i == "dev") {
                    print $(i+1)
                    exit
                }
        }'
    )

    HOST_IP=$(
        printf '%s\n' "$ROUTE_INFO" |
        awk '{
            for (i = 1; i <= NF; i++)
                if ($i == "src") {
                    print $(i+1)
                    exit
                }
        }'
    )

elif [[ "$OS" == "Darwin" ]]; then

    # macOS: detect interface used to reach the LIMO
    NETWORK_INTERFACE=$(
        route -n get "$LIMO_IP" 2>/dev/null |
        awk '/interface:/ {print $2; exit}'
    )

    # macOS: get the IPv4 address assigned to the interface
    if [[ -n "$NETWORK_INTERFACE" ]]; then
        HOST_IP=$(ipconfig getifaddr "$NETWORK_INTERFACE" 2>/dev/null)
    fi
fi

if [[ -z "$NETWORK_INTERFACE" ]]; then
    echo "Error: could not detect the network interface."
    return 1
fi

if [[ -z "$HOST_IP" ]] || ! valid_ipv4 "$HOST_IP"; then
    echo "Error: could not detect a valid local IPv4 address."
    return 1
fi

echo "Detected network interface: $NETWORK_INTERFACE"
echo "Detected host PC IP: $HOST_IP"

# ============================================================
# 7. CYCLONEDDS XML PATH
# ============================================================

DEFAULT_XML="$HOME/cyclonedds.xml"

echo ""
echo "Suggested CycloneDDS XML path: $DEFAULT_XML"

read -rp "Press Enter to accept, or enter another path: " XML_PATH

XML_PATH="${XML_PATH:-$DEFAULT_XML}"

# Expand ~/ path
if [[ "$XML_PATH" == "~/"* ]]; then
    XML_PATH="$HOME/${XML_PATH#\~/}"
fi

if [[ "$XML_PATH" != /* ]]; then
    echo "Error: XML path must be absolute."
    return 1
fi

if ! mkdir -p "$(dirname "$XML_PATH")"; then
    echo "Error: cannot create XML directory."
    return 1
fi

# ============================================================
# 8. BACKUP EXISTING XML
# ============================================================

if [[ -f "$XML_PATH" ]]; then
    echo ""
    echo "Existing XML file: $XML_PATH"

    read -rp "Overwrite this file? (y/N): " CONFIRM

    if [[ ! "$CONFIRM" =~ ^[Yy]$ ]]; then
        echo "Setup cancelled. Existing XML preserved."
        return 1
    fi

    if ! cp "$XML_PATH" "${XML_PATH}.bak"; then
        echo "Error: failed to create XML backup."
        return 1
    fi

    echo "Backup created: ${XML_PATH}.bak"
fi

# ============================================================
# 9. GENERATE CYCLONEDDS XML
# ============================================================

if ! cat > "$XML_PATH" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!-- CycloneDDS configuration for ROS 2 host PC -->
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
        <!-- Remote LIMO robot -->
        <Peer Address="${LIMO_IP}"/>

        <!-- Local host PC -->
        <Peer Address="${HOST_IP}"/>
      </Peers>
    </Discovery>
  </Domain>
</CycloneDDS>
EOF
then
    echo "Error: failed to write CycloneDDS XML."
    return 1
fi

# ============================================================
# 10. CONFIGURE ROS 2 ENVIRONMENT
# ============================================================

export RMW_IMPLEMENTATION=rmw_cyclonedds_cpp
export CYCLONEDDS_URI="file://${XML_PATH}"
export ROS_LOCALHOST_ONLY=0

# ============================================================
# 11. CONFIGURATION SUMMARY
# ============================================================

echo ""
echo "============================================"
echo " ROS 2 LIMO HOST CONFIGURATION COMPLETE"
echo "============================================"
echo "Operating system : $OS"
echo "ROS distribution : ${ROS_DISTRO:-unknown}"
echo "LIMO number      : $LIMO_NUMBER"
echo "LIMO namespace   : $LIMO_NAMESPACE"
echo "LIMO IP          : $LIMO_IP"
echo "Host PC IP       : $HOST_IP"
echo "Network interface: $NETWORK_INTERFACE"
echo "ROS domain ID    : $ROS_DOMAIN_ID"
echo "DDS middleware   : $RMW_IMPLEMENTATION"
echo "CycloneDDS XML   : $XML_PATH"
echo "CYCLONEDDS_URI   : $CYCLONEDDS_URI"
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
