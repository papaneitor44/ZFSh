#!/bin/bash
# zfs-incus-init.sh - Initialize Incus with existing ZFS pool
#
# Usage: zfs-incus-init.sh [OPTIONS]
#
# Options:
#   -p, --pool NAME         ZFS pool name (default: default)
#   -s, --storage NAME      Incus storage pool name (default: same as ZFS pool)
#   -n, --network NAME      Bridge network name (default: incusbr0)
#   --network-ipv4 CIDR     IPv4 subnet (default: auto)
#   --no-network            Skip network creation
#   -y, --yes               Skip confirmation
#   -j, --json              Output as JSON
#   -l, --log FILE          Log to file
#   -q, --quiet             Minimal output
#   -h, --help              Show help

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

# =============================================================================
# DEFAULTS
# =============================================================================
ZFS_POOL="default"
STORAGE_NAME=""
NETWORK_NAME="incusbr0"
NETWORK_IPV4=""
CREATE_NETWORK=true
SKIP_CONFIRM=false

# =============================================================================
# FUNCTIONS
# =============================================================================
show_help() {
    cat << 'EOF'
ZFS Incus Init - Initialize Incus with existing ZFS pool

Usage: zfs-incus-init.sh [OPTIONS]

Options:
  -p, --pool NAME         ZFS pool name (default: default)
  -s, --storage NAME      Incus storage pool name (default: same as ZFS pool)
  -n, --network NAME      Bridge network name (default: incusbr0)
  --network-ipv4 CIDR     IPv4 subnet (default: auto)
  --no-network            Skip network creation
  -y, --yes               Skip confirmation
  -j, --json              Output as JSON
  -l, --log FILE          Log to file
  -q, --quiet             Minimal output
  -h, --help              Show this help

Examples:
  # Interactive mode
  zfs-incus-init.sh

  # Use specific ZFS pool
  zfs-incus-init.sh -p mypool -y

  # Custom storage and network names
  zfs-incus-init.sh -p default -s storage -n br0 -y

  # Skip network creation
  zfs-incus-init.sh -p default --no-network -y

  # With specific IPv4 subnet
  zfs-incus-init.sh -p default --network-ipv4 10.100.0.1/24 -y
EOF
}

check_prerequisites() {
    check_root
    check_zfs_installed
    check_incus_installed
    
    # Check ZFS pool exists
    if ! pool_exists "$ZFS_POOL"; then
        die "ZFS pool '$ZFS_POOL' does not exist"
    fi
    
    # Check pool is online
    local health
    health=$(zpool get -H -o value health "$ZFS_POOL")
    if [[ "$health" != "ONLINE" ]]; then
        die "ZFS pool '$ZFS_POOL' is not ONLINE (status: $health)"
    fi
    
    # Check if Incus storage pool already exists
    if incus storage list 2>/dev/null | grep -q "^| $STORAGE_NAME "; then
        die "Incus storage pool '$STORAGE_NAME' already exists"
    fi
    
    # Check if network already exists (if creating)
    if [[ "$CREATE_NETWORK" == "true" ]]; then
        if incus network list 2>/dev/null | grep -q "^| $NETWORK_NAME "; then
            warn "Network '$NETWORK_NAME' already exists, will use existing"
            CREATE_NETWORK=false
        fi
    fi
}

list_pools() {
    local pools
    pools=$(get_pools)
    
    if [[ -z "$pools" ]]; then
        die "No ZFS pools found. Create one first with zfs-pool-create.sh"
    fi
    
    echo "Available ZFS pools:"
    local i=1
    local pool_array=()
    while IFS= read -r pool; do
        local size health
        size=$(zpool get -H -o value size "$pool")
        health=$(zpool get -H -o value health "$pool")
        echo "  $i. $pool ($size, $health)"
        pool_array+=("$pool")
        ((i++))
    done <<< "$pools"
    
    echo ""
    while true; do
        read -rp "Select pool [1-${#pool_array[@]}]: " selection
        if [[ "$selection" =~ ^[0-9]+$ ]] && [[ "$selection" -ge 1 ]] && [[ "$selection" -le ${#pool_array[@]} ]]; then
            ZFS_POOL="${pool_array[$((selection-1))]}"
            return 0
        fi
        echo "Invalid selection"
    done
}

generate_preseed() {
    local preseed=""
    
    # Storage pool config
    preseed+="storage_pools:
- name: $STORAGE_NAME
  driver: zfs
  config:
    source: $ZFS_POOL
"
    
    # Network config
    if [[ "$CREATE_NETWORK" == "true" ]]; then
        preseed+="networks:
- name: $NETWORK_NAME
  type: bridge
"
        if [[ -n "$NETWORK_IPV4" ]]; then
            preseed+="  config:
    ipv4.address: $NETWORK_IPV4
    ipv4.nat: \"true\"
"
        fi
    fi
    
    # Default profile
    preseed+="profiles:
- name: default
  devices:
    root:
      path: /
      pool: $STORAGE_NAME
      type: disk
"
    
    if [[ "$CREATE_NETWORK" == "true" ]] || incus network list 2>/dev/null | grep -q "^| $NETWORK_NAME "; then
        preseed+="    eth0:
      name: eth0
      network: $NETWORK_NAME
      type: nic
"
    fi
    
    echo "$preseed"
}

show_summary() {
    if [[ "$JSON_OUTPUT" == "false" && "$QUIET" == "false" ]]; then
        echo ""
        echo "Summary:"
        echo "  ZFS pool:      $ZFS_POOL"
        echo "  Storage name:  $STORAGE_NAME"
        if [[ "$CREATE_NETWORK" == "true" ]]; then
            echo "  Network:       $NETWORK_NAME (create new)"
            if [[ -n "$NETWORK_IPV4" ]]; then
                echo "  Network IPv4:  $NETWORK_IPV4"
            fi
        else
            echo "  Network:       $NETWORK_NAME (use existing)"
        fi
        echo ""
    fi
}

apply_preseed() {
    local preseed
    preseed=$(generate_preseed)
    
    info "Applying Incus configuration..."
    
    if [[ "$QUIET" == "false" && "$JSON_OUTPUT" == "false" ]]; then
        echo "Preseed configuration:"
        echo "---"
        echo "$preseed"
        echo "---"
        echo ""
    fi
    
    echo "$preseed" | incus admin init --preseed
    
    success "Incus initialized successfully"
}

verify_setup() {
    info "Verifying setup..."
    
    # Check storage pool
    if incus storage list 2>/dev/null | grep -q "^| $STORAGE_NAME "; then
        success "Storage pool '$STORAGE_NAME' created"
    else
        error "Storage pool '$STORAGE_NAME' not found"
        return 1
    fi
    
    # Check network
    if incus network list 2>/dev/null | grep -q "^| $NETWORK_NAME "; then
        success "Network '$NETWORK_NAME' available"
    else
        warn "Network '$NETWORK_NAME' not found"
    fi
    
    # Check default profile
    if incus profile show default 2>/dev/null | grep -q "pool: $STORAGE_NAME"; then
        success "Default profile configured"
    else
        warn "Default profile may not be configured correctly"
    fi
}

output_result() {
    if [[ "$JSON_OUTPUT" == "true" ]]; then
        # Get storage pool info
        local storage_info network_info
        storage_info=$(incus storage show "$STORAGE_NAME" 2>/dev/null || echo "")
        
        local network_ipv4=""
        if incus network list 2>/dev/null | grep -q "^| $NETWORK_NAME "; then
            network_ipv4=$(incus network get "$NETWORK_NAME" ipv4.address 2>/dev/null || echo "")
        fi
        
        cat << EOF
{
  "success": true,
  "storage": {
    "name": "$STORAGE_NAME",
    "driver": "zfs",
    "source": "$ZFS_POOL"
  },
  "network": {
    "name": "$NETWORK_NAME",
    "ipv4": "$network_ipv4"
  }
}
EOF
    else
        echo ""
        echo "Setup complete! You can now create containers:"
        echo ""
        echo "  incus launch images:debian/12 my-container"
        echo "  incus launch images:ubuntu/24.04 my-ubuntu"
        echo ""
        echo "Useful commands:"
        echo "  incus list                    # List containers"
        echo "  incus storage info $STORAGE_NAME    # Storage info"
        echo "  incus network list            # List networks"
    fi
}

interactive_mode() {
    header "Incus Initialization with ZFS"
    
    list_pools
    
    prompt "Incus storage pool name" "$ZFS_POOL"
    STORAGE_NAME="$REPLY"
    
    if prompt_yn "Create bridge network?" "y"; then
        CREATE_NETWORK=true
        prompt "Network name" "$NETWORK_NAME"
        NETWORK_NAME="$REPLY"
        
        prompt "IPv4 subnet (leave empty for auto)" ""
        NETWORK_IPV4="$REPLY"
    else
        CREATE_NETWORK=false
        prompt "Existing network name to use" "$NETWORK_NAME"
        NETWORK_NAME="$REPLY"
    fi
}

# =============================================================================
# ARGUMENT PARSING
# =============================================================================
parse_args() {
    parse_common_args "$@"
    set -- "${REMAINING_ARGS[@]}"
    
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -p|--pool)
                ZFS_POOL="$2"
                shift 2
                ;;
            -s|--storage)
                STORAGE_NAME="$2"
                shift 2
                ;;
            -n|--network)
                NETWORK_NAME="$2"
                shift 2
                ;;
            --network-ipv4)
                NETWORK_IPV4="$2"
                shift 2
                ;;
            --no-network)
                CREATE_NETWORK=false
                shift
                ;;
            -y|--yes)
                SKIP_CONFIRM=true
                shift
                ;;
            -h|--help)
                show_help
                exit 0
                ;;
            *)
                die "Unknown option: $1 (use -h for help)"
                ;;
        esac
    done
    
    # Default storage name to pool name
    if [[ -z "$STORAGE_NAME" ]]; then
        STORAGE_NAME="$ZFS_POOL"
    fi
}

# =============================================================================
# MAIN
# =============================================================================
main() {
    parse_args "$@"
    
    # Interactive mode if running without -y and pool is default
    if [[ "$SKIP_CONFIRM" == "false" && "$ZFS_POOL" == "default" ]]; then
        # Check if default pool exists, if not go interactive
        if ! pool_exists "$ZFS_POOL"; then
            interactive_mode
        fi
    fi
    
    # Set default storage name if not set
    if [[ -z "$STORAGE_NAME" ]]; then
        STORAGE_NAME="$ZFS_POOL"
    fi
    
    check_prerequisites
    show_summary
    
    # Confirm unless -y
    if [[ "$SKIP_CONFIRM" == "false" ]]; then
        if ! confirm "Initialize Incus with these settings?"; then
            echo "Aborted."
            exit 0
        fi
    fi
    
    apply_preseed
    verify_setup
    output_result
}

main "$@"
