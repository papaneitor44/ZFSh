#!/bin/bash
# zfs-pool-expand.sh - Expand ZFS pool size (for file-backed pools)
#
# Usage: zfs-pool-expand.sh [POOL_NAME] [OPTIONS]
#
# Options:
#   -s, --size SIZE    New total size (e.g. 100G)
#   -a, --add SIZE     Add size to current (e.g. +50G)
#   -y, --yes          Skip confirmation
#   -j, --json         Output as JSON
#   -l, --log FILE     Log to file
#   -q, --quiet        Minimal output
#   -h, --help         Show help

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

# =============================================================================
# DEFAULTS
# =============================================================================
POOL_NAME=""
NEW_SIZE=""
ADD_SIZE=""
SKIP_CONFIRM=false

# =============================================================================
# FUNCTIONS
# =============================================================================
show_help() {
    cat << 'EOF'
ZFS Pool Expand - Expand ZFS pool size (for file-backed pools)

Usage: zfs-pool-expand.sh [POOL_NAME] [OPTIONS]

Options:
  -s, --size SIZE    New total size (e.g. 100G)
  -a, --add SIZE     Add size to current (e.g. +50G)
  -y, --yes          Skip confirmation
  -j, --json         Output as JSON
  -l, --log FILE     Log to file
  -q, --quiet        Minimal output
  -h, --help         Show this help

Examples:
  # Interactive mode
  zfs-pool-expand.sh

  # Expand to specific size
  zfs-pool-expand.sh default -s 100G -y

  # Add 50G to current size
  zfs-pool-expand.sh default -a 50G -y

  # Output as JSON
  zfs-pool-expand.sh default -s 100G -y --json

Note: This only works for file-backed pools (sparse file).
EOF
}

list_pools() {
    local pools
    pools=$(get_pools)
    
    if [[ -z "$pools" ]]; then
        die "No ZFS pools found"
    fi
    
    echo "Available pools:"
    local i=1
    local pool_array=()
    while IFS= read -r pool; do
        local backend_type size health
        backend_type=$(get_pool_backend_type "$pool")
        size=$(zpool get -H -o value size "$pool")
        health=$(zpool get -H -o value health "$pool")
        
        local type_indicator=""
        if [[ "$backend_type" != "file" ]]; then
            type_indicator=" [device - cannot expand]"
        fi
        
        echo "  $i. $pool ($size, $health)$type_indicator"
        pool_array+=("$pool")
        ((i++))
    done <<< "$pools"
    
    echo ""
    while true; do
        read -rp "Select pool [1-${#pool_array[@]}]: " selection
        if [[ "$selection" =~ ^[0-9]+$ ]] && [[ "$selection" -ge 1 ]] && [[ "$selection" -le ${#pool_array[@]} ]]; then
            POOL_NAME="${pool_array[$((selection-1))]}"
            return 0
        fi
        echo "Invalid selection"
    done
}

check_prerequisites() {
    check_root
    check_zfs_installed
    
    # Check pool exists
    if ! pool_exists "$POOL_NAME"; then
        die "Pool '$POOL_NAME' does not exist"
    fi
    
    # Check pool is file-backed
    local backend_type
    backend_type=$(get_pool_backend_type "$POOL_NAME")
    if [[ "$backend_type" != "file" ]]; then
        die "Pool '$POOL_NAME' is not file-backed (type: $backend_type). Cannot expand."
    fi
    
    # Check pool is online
    local health
    health=$(zpool get -H -o value health "$POOL_NAME")
    if [[ "$health" != "ONLINE" ]]; then
        die "Pool '$POOL_NAME' is not ONLINE (status: $health)"
    fi
}

get_current_info() {
    BACKEND_PATH=$(get_pool_backend_path "$POOL_NAME")
    CURRENT_SIZE_BYTES=$(zpool get -H -o value -p size "$POOL_NAME")
    CURRENT_SIZE=$(format_size "$CURRENT_SIZE_BYTES")
    CURRENT_USED_BYTES=$(zpool get -H -o value -p allocated "$POOL_NAME")
    CURRENT_USED=$(format_size "$CURRENT_USED_BYTES")
    
    # Get available space on filesystem
    local fs_free
    fs_free=$(get_free_space "$(dirname "$BACKEND_PATH")")
    AVAILABLE_SPACE=$(format_size "$fs_free")
    AVAILABLE_SPACE_BYTES=$fs_free
}

calculate_new_size() {
    if [[ -n "$ADD_SIZE" ]]; then
        # Remove + prefix if present
        local add="${ADD_SIZE#+}"
        local add_bytes
        add_bytes=$(parse_size "$add")
        NEW_SIZE_BYTES=$((CURRENT_SIZE_BYTES + add_bytes))
        NEW_SIZE=$(format_size "$NEW_SIZE_BYTES")
    elif [[ -n "$NEW_SIZE" ]]; then
        NEW_SIZE_BYTES=$(parse_size "$NEW_SIZE")
        # Validate new size is larger
        if [[ $NEW_SIZE_BYTES -le $CURRENT_SIZE_BYTES ]]; then
            die "New size ($NEW_SIZE) must be larger than current size ($CURRENT_SIZE)"
        fi
    else
        die "No size specified"
    fi
    
    # Check we have enough space
    local needed=$((NEW_SIZE_BYTES - CURRENT_SIZE_BYTES))
    if [[ $needed -gt $AVAILABLE_SPACE_BYTES ]]; then
        die "Not enough free space. Need: $(format_size $needed), Available: $AVAILABLE_SPACE"
    fi
}

show_summary() {
    if [[ "$JSON_OUTPUT" == "false" && "$QUIET" == "false" ]]; then
        echo ""
        echo "Pool:            $POOL_NAME"
        echo "Backend:         $BACKEND_PATH"
        echo "Current size:    $CURRENT_SIZE"
        echo "Current used:    $CURRENT_USED"
        echo "New size:        $NEW_SIZE"
        echo "Available space: $AVAILABLE_SPACE"
        echo ""
    fi
}

expand_pool() {
    info "Expanding sparse file to $NEW_SIZE..."
    truncate -s "$NEW_SIZE_BYTES" "$BACKEND_PATH"
    
    info "Notifying ZFS of new size..."
    zpool online -e "$POOL_NAME" "$BACKEND_PATH"
    
    # Get actual new size from ZFS
    local actual_new_size
    actual_new_size=$(zpool get -H -o value size "$POOL_NAME")
    
    success "Pool expanded to $actual_new_size"
}

output_result() {
    if [[ "$JSON_OUTPUT" == "true" ]]; then
        local new_total_bytes new_free_bytes
        new_total_bytes=$(zpool get -H -o value -p size "$POOL_NAME")
        new_free_bytes=$(zpool get -H -o value -p free "$POOL_NAME")
        
        cat << EOF
{
  "success": true,
  "pool": "$POOL_NAME",
  "previous_size": $CURRENT_SIZE_BYTES,
  "new_size": $new_total_bytes,
  "new_size_human": "$(format_size $new_total_bytes)",
  "free": $new_free_bytes,
  "free_human": "$(format_size $new_free_bytes)"
}
EOF
    fi
}

interactive_mode() {
    header "Expand ZFS Pool"
    
    list_pools
    check_prerequisites
    get_current_info
    
    echo ""
    echo "Pool:            $POOL_NAME"
    echo "Current size:    $CURRENT_SIZE"
    echo "Current used:    $CURRENT_USED"
    echo "Backend:         $BACKEND_PATH"
    echo "Available space: $AVAILABLE_SPACE"
    echo ""
    echo "Enter new size:"
    echo "  - Absolute size (e.g. 100G)"
    echo "  - Or increment (e.g. +50G)"
    echo ""
    
    prompt "New size" ""
    local input="$REPLY"
    
    if [[ "$input" == +* ]]; then
        ADD_SIZE="$input"
    else
        NEW_SIZE="$input"
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
            -s|--size)
                NEW_SIZE="$2"
                shift 2
                ;;
            -a|--add)
                ADD_SIZE="$2"
                shift 2
                ;;
            -y|--yes)
                SKIP_CONFIRM=true
                shift
                ;;
            -h|--help)
                show_help
                exit 0
                ;;
            -*)
                die "Unknown option: $1 (use -h for help)"
                ;;
            *)
                POOL_NAME="$1"
                shift
                ;;
        esac
    done
}

# =============================================================================
# MAIN
# =============================================================================
main() {
    parse_args "$@"
    
    # Interactive mode if no pool or size specified
    if [[ -z "$POOL_NAME" || ( -z "$NEW_SIZE" && -z "$ADD_SIZE" ) ]]; then
        interactive_mode
    fi
    
    check_prerequisites
    get_current_info
    calculate_new_size
    show_summary
    
    # Confirm unless -y
    if [[ "$SKIP_CONFIRM" == "false" ]]; then
        if ! confirm "Expand pool from $CURRENT_SIZE to $NEW_SIZE?"; then
            echo "Aborted."
            exit 0
        fi
    fi
    
    expand_pool
    output_result
}

main "$@"
