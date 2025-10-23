#!/bin/sh
# AmneziaWG Policy Routing Engine
# Manages routing tables, rules, and traffic policies

set -e

# Constants
ROUTING_TABLE_BASE=200
FWMARK_BASE=0x1000
PRIORITY_BASE=1000

# Configuration paths
CONF_DIR="/jffs/amneziawg"
STATE_DIR="${CONF_DIR}/state"
ROUTING_STATE="${STATE_DIR}/routing"

# Logging
log_info() {
    logger -t "amneziawg-routing" -p user.info "$*"
}

log_error() {
    logger -t "amneziawg-routing" -p user.err "$*"
}

# Get routing table number for interface
get_table_number() {
    local iface="$1"
    local iface_num
    
    # Extract number from interface name (e.g., awg0 -> 0)
    iface_num=$(echo "${iface}" | sed 's/awg//')
    echo $((ROUTING_TABLE_BASE + iface_num))
}

# Get fwmark for interface
get_fwmark() {
    local iface="$1"
    local iface_num
    
    iface_num=$(echo "${iface}" | sed 's/awg//')
    printf "0x%x" $((FWMARK_BASE + iface_num))
}

# Get priority for rule
get_priority() {
    local iface="$1"
    local iface_num
    
    iface_num=$(echo "${iface}" | sed 's/awg//')
    echo $((PRIORITY_BASE + iface_num))
}

# Setup routing table
setup_routing_table() {
    local iface="$1"
    local table_num
    local gateway
    
    table_num=$(get_table_number "${iface}")
    gateway=$(ip -4 route show dev "${iface}" | grep -m1 '^' | awk '{print $1}')
    
    log_info "Setting up routing table ${table_num} for ${iface}"
    
    # Add default route to table
    if [ -n "${gateway}" ]; then
        ip route add default dev "${iface}" table "${table_num}" 2>/dev/null || true
    else
        ip route add default dev "${iface}" table "${table_num}" 2>/dev/null || true
    fi
    
    # Add local routes
    ip route show table main | grep -v default | while read -r route; do
        ip route add ${route} table "${table_num}" 2>/dev/null || true
    done
}

# Setup policy routing rules
setup_policy_rules() {
    local iface="$1"
    local table_num
    local fwmark
    local priority
    
    table_num=$(get_table_number "${iface}")
    fwmark=$(get_fwmark "${iface}")
    priority=$(get_priority "${iface}")
    
    log_info "Setting up policy rules for ${iface}"
    
    # Add fwmark rule
    ip rule add fwmark "${fwmark}" table "${table_num}" priority "${priority}" 2>/dev/null || true
    
    # Add interface rule
    ip rule add iif "${iface}" table "${table_num}" priority $((priority + 1)) 2>/dev/null || true
}

# Setup source-based routing
setup_source_routing() {
    local iface="$1"
    local source_ips="$2"
    local table_num
    local priority
    
    table_num=$(get_table_number "${iface}")
    priority=$(get_priority "${iface}")
    
    log_info "Setting up source routing for ${iface}"
    
    # Add rules for each source IP/network
    echo "${source_ips}" | tr ',' '\n' | while read -r source; do
        [ -z "${source}" ] && continue
        ip rule add from "${source}" table "${table_num}" priority $((priority + 10)) 2>/dev/null || true
    done
}

# Setup destination-based routing
setup_destination_routing() {
    local iface="$1"
    local dest_ips="$2"
    local table_num
    local priority
    
    table_num=$(get_table_number "${iface}")
    priority=$(get_priority "${iface}")
    
    log_info "Setting up destination routing for ${iface}"
    
    # Add rules for each destination IP/network
    echo "${dest_ips}" | tr ',' '\n' | while read -r dest; do
        [ -z "${dest}" ] && continue
        ip rule add to "${dest}" table "${table_num}" priority $((priority + 20)) 2>/dev/null || true
    done
}

# Setup port-based routing
setup_port_routing() {
    local iface="$1"
    local ports="$2"
    local fwmark
    
    fwmark=$(get_fwmark "${iface}")
    
    log_info "Setting up port-based routing for ${iface}"
    
    # Mark packets by port
    echo "${ports}" | tr ',' '\n' | while read -r port; do
        [ -z "${port}" ] && continue
        iptables -t mangle -A PREROUTING -p tcp --dport "${port}" -j MARK --set-mark "${fwmark}" 2>/dev/null || true
        iptables -t mangle -A PREROUTING -p udp --dport "${port}" -j MARK --set-mark "${fwmark}" 2>/dev/null || true
    done
}

# Setup LAN client routing
setup_lan_routing() {
    local iface="$1"
    local lan_clients="$2"
    local table_num
    local priority
    
    table_num=$(get_table_number "${iface}")
    priority=$(get_priority "${iface}")
    
    log_info "Setting up LAN client routing for ${iface}"
    
    # Add rules for each LAN client
    echo "${lan_clients}" | tr ',' '\n' | while read -r client; do
        [ -z "${client}" ] && continue
        ip rule add from "${client}" table "${table_num}" priority $((priority + 30)) 2>/dev/null || true
    done
}

# Cleanup routing for interface
cleanup_routing() {
    local iface="$1"
    local table_num
    local fwmark
    local priority
    
    table_num=$(get_table_number "${iface}")
    fwmark=$(get_fwmark "${iface}")
    priority=$(get_priority "${iface}")
    
    log_info "Cleaning up routing for ${iface}"
    
    # Remove policy rules
    ip rule list | grep "lookup ${table_num}" | while read -r rule; do
        prio=$(echo "${rule}" | sed -n 's/.*priority \([0-9]*\).*/\1/p')
        [ -n "${prio}" ] && ip rule del priority "${prio}" 2>/dev/null || true
    done
    
    # Flush routing table
    ip route flush table "${table_num}" 2>/dev/null || true
    
    # Remove iptables marks
    iptables -t mangle -S PREROUTING | grep "${fwmark}" | while read -r rule; do
        iptables -t mangle -D PREROUTING $(echo "${rule}" | sed 's/^-A PREROUTING //') 2>/dev/null || true
    done
}

# Apply full routing configuration
apply_routing() {
    local iface="$1"
    local config_file="${CONF_DIR}/${iface}.conf"
    
    [ ! -f "${config_file}" ] && {
        log_error "Configuration file not found: ${config_file}"
        return 1
    }
    
    log_info "Applying routing configuration for ${iface}"
    
    # Setup basic routing
    setup_routing_table "${iface}"
    setup_policy_rules "${iface}"
    
    # Load and apply policy routing settings
    . "${config_file}"
    
    [ -n "${POLICY_SOURCE_IPS}" ] && setup_source_routing "${iface}" "${POLICY_SOURCE_IPS}"
    [ -n "${POLICY_DEST_IPS}" ] && setup_destination_routing "${iface}" "${POLICY_DEST_IPS}"
    [ -n "${POLICY_PORTS}" ] && setup_port_routing "${iface}" "${POLICY_PORTS}"
    [ -n "${POLICY_LAN_CLIENTS}" ] && setup_lan_routing "${iface}" "${POLICY_LAN_CLIENTS}"
    
    # Save routing state
    mkdir -p "${ROUTING_STATE}"
    echo "applied" > "${ROUTING_STATE}/${iface}.state"
    
    log_info "Routing configuration applied for ${iface}"
}

# Remove routing configuration
remove_routing() {
    local iface="$1"
    
    log_info "Removing routing configuration for ${iface}"
    
    cleanup_routing "${iface}"
    
    # Remove state
    rm -f "${ROUTING_STATE}/${iface}.state"
    
    log_info "Routing configuration removed for ${iface}"
}

# Show routing status
show_routing() {
    local iface="$1"
    local table_num
    local fwmark
    local priority
    
    table_num=$(get_table_number "${iface}")
    fwmark=$(get_fwmark "${iface}")
    priority=$(get_priority "${iface}")
    
    echo "Routing configuration for ${iface}:"
    echo "  Table: ${table_num}"
    echo "  FWMark: ${fwmark}"
    echo "  Priority: ${priority}"
    echo ""
    echo "Routes:"
    ip route show table "${table_num}"
    echo ""
    echo "Rules:"
    ip rule list | grep "lookup ${table_num}"
    echo ""
    echo "IPTables marks:"
    iptables -t mangle -S PREROUTING | grep "${fwmark}"
}

# Main command handler
main() {
    local command="$1"
    local iface="$2"
    
    case "${command}" in
        apply)
            [ -z "${iface}" ] && {
                log_error "Interface name required"
                exit 1
            }
            apply_routing "${iface}"
            ;;
        remove)
            [ -z "${iface}" ] && {
                log_error "Interface name required"
                exit 1
            }
            remove_routing "${iface}"
            ;;
        show)
            [ -z "${iface}" ] && {
                log_error "Interface name required"
                exit 1
            }
            show_routing "${iface}"
            ;;
        cleanup)
            [ -z "${iface}" ] && {
                log_error "Interface name required"
                exit 1
            }
            cleanup_routing "${iface}"
            ;;
        *)
            echo "Usage: $0 {apply|remove|show|cleanup} <interface>"
            exit 1
            ;;
    esac
}

main "$@"
