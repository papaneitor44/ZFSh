#!/bin/bash
# zfs-pool-info.sh - Display detailed information about ZFS pool
#
# Usage: zfs-pool-info.sh [POOL_NAME] [OPTIONS]
#
# Options:
#   -a, --all       Show all details including datasets
#   -j, --json      Output as JSON
#   -l, --log FILE  Log to file
#   -q, --quiet     Minimal output
#   -h, --help      Show help

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

# =============================================================================
# DEFAULTS
# =============================================================================
POOL_NAME=""
SHOW_ALL=false

# =============================================================================
# FUNCTIONS
# =============================================================================
show_help() {
    cat << 'EOF'
ZFS Pool Info - Display detailed information about ZFS pool

Usage: zfs-pool-info.sh [POOL_NAME] [OPTIONS]

Options:
  -a, --all       Show all details including datasets
  -j, --json      Output as JSON
  -l, --log FILE  Log to file
  -q, --quiet     Minimal output
  -h, --help      Show this help

Examples:
  # Interactive - select from available pools
  zfs-pool-info.sh

  # Show info for specific pool
  zfs-pool-info.sh default

  # Show all details
  zfs-pool-info.sh default -a

  # Output as JSON
  zfs-pool-info.sh default --json
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
            POOL_NAME="${pool_array[$((selection-1))]}"
            return 0
        fi
        echo "Invalid selection"
    done
}

get_pool_info() {
    local pool="$1"
    
    # Basic info
    POOL_STATUS=$(zpool get -H -o value health "$pool")
    POOL_STATE=$(zpool list -H -o health "$pool")
    
    # Storage
    POOL_SIZE=$(zpool get -H -o value size "$pool")
    POOL_ALLOC=$(zpool get -H -o value allocated "$pool")
    POOL_FREE=$(zpool get -H -o value free "$pool")
    POOL_FRAG=$(zpool get -H -o value fragmentation "$pool")
    POOL_CAP=$(zpool get -H -o value capacity "$pool")
    POOL_DEDUP_RATIO=$(zpool get -H -o value dedupratio "$pool")
    
    # Properties
    POOL_AUTOTRIM=$(zpool get -H -o value autotrim "$pool")
    POOL_COMPRESSION=$(zfs get -H -o value compression "$pool")
    POOL_DEDUP=$(zfs get -H -o value dedup "$pool")
    
    # Backend info
    POOL_BACKEND_PATH=$(get_pool_backend_path "$pool")
    POOL_BACKEND_TYPE=$(get_pool_backend_type "$pool")
    
    if [[ "$POOL_BACKEND_TYPE" == "file" && -f "$POOL_BACKEND_PATH" ]]; then
        POOL_SPARSE_SIZE=$(du -h "$POOL_BACKEND_PATH" | cut -f1)
        POOL_SPARSE_BYTES=$(du -b "$POOL_BACKEND_PATH" | cut -f1)
    else
        POOL_SPARSE_SIZE="N/A"
        POOL_SPARSE_BYTES=0
    fi
    
    # Datasets
    if [[ "$SHOW_ALL" == "true" ]]; then
        POOL_DATASETS=$(zfs list -H -o name,used,available,refer -r "$pool")
    fi
}

format_text_output() {
    local pool="$1"
    
    header "ZFS Pool: $pool"
    
    echo ""
    echo "Status"
    echo "------"
    echo "  State:         $POOL_STATE"
    echo "  Health:        $POOL_STATUS"
    
    echo ""
    echo "Storage"
    echo "-------"
    echo "  Total:         $POOL_SIZE"
    echo "  Used:          $POOL_ALLOC ($POOL_CAP)"
    echo "  Free:          $POOL_FREE"
    echo "  Fragmentation: $POOL_FRAG"
    echo "  Dedup Ratio:   $POOL_DEDUP_RATIO"
    
    echo ""
    echo "Properties"
    echo "----------"
    echo "  Compression:   $POOL_COMPRESSION"
    echo "  Dedup:         $POOL_DEDUP"
    echo "  Autotrim:      $POOL_AUTOTRIM"
    
    echo ""
    echo "Backend"
    echo "-------"
    echo "  Type:          $POOL_BACKEND_TYPE"
    echo "  Path:          $POOL_BACKEND_PATH"
    if [[ "$POOL_BACKEND_TYPE" == "file" ]]; then
        echo "  Actual Size:   $POOL_SPARSE_SIZE (sparse)"
    fi
    
    if [[ "$SHOW_ALL" == "true" && -n "${POOL_DATASETS:-}" ]]; then
        echo ""
        echo "Datasets"
        echo "--------"
        echo "  NAME                          USED    AVAIL   REFER"
        while IFS=$'\t' read -r name used avail refer; do
            printf "  %-30s %-7s %-7s %s\n" "$name" "$used" "$avail" "$refer"
        done <<< "$POOL_DATASETS"
    fi
}

format_json_output() {
    local pool="$1"
    
    # Get numeric values
    local total_bytes used_bytes free_bytes
    total_bytes=$(zpool get -H -o value -p size "$pool")
    used_bytes=$(zpool get -H -o value -p allocated "$pool")
    free_bytes=$(zpool get -H -o value -p free "$pool")
    
    # Parse dedup ratio (remove 'x')
    local dedup_ratio="${POOL_DEDUP_RATIO//x/}"
    
    # Parse capacity (remove '%')
    local capacity="${POOL_CAP//%/}"
    
    # Parse fragmentation (remove '%')
    local frag="${POOL_FRAG//%/}"
    
    # Build datasets JSON array
    local datasets_json="[]"
    if [[ "$SHOW_ALL" == "true" && -n "${POOL_DATASETS:-}" ]]; then
        datasets_json="["
        local first=true
        while IFS=$'\t' read -r name used avail refer; do
            if [[ "$first" == "true" ]]; then
                first=false
            else
                datasets_json+=","
            fi
            datasets_json+="{\"name\":\"$name\",\"used\":\"$used\",\"available\":\"$avail\",\"refer\":\"$refer\"}"
        done <<< "$POOL_DATASETS"
        datasets_json+="]"
    fi
    
    cat << EOF
{
  "pool": "$pool",
  "status": {
    "state": "$POOL_STATE",
    "health": "$POOL_STATUS"
  },
  "storage": {
    "total": $total_bytes,
    "total_human": "$POOL_SIZE",
    "used": $used_bytes,
    "used_human": "$POOL_ALLOC",
    "free": $free_bytes,
    "free_human": "$POOL_FREE",
    "capacity_percent": $capacity,
    "fragmentation_percent": ${frag:-0},
    "dedup_ratio": $dedup_ratio
  },
  "properties": {
    "compression": "$POOL_COMPRESSION",
    "dedup": "$POOL_DEDUP",
    "autotrim": "$POOL_AUTOTRIM"
  },
  "backend": {
    "type": "$POOL_BACKEND_TYPE",
    "path": "$POOL_BACKEND_PATH",
    "sparse_size": $POOL_SPARSE_BYTES
  },
  "datasets": $datasets_json
}
EOF
}

# =============================================================================
# ARGUMENT PARSING
# =============================================================================
parse_args() {
    parse_common_args "$@"
    set -- "${REMAINING_ARGS[@]}"
    
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -a|--all)
                SHOW_ALL=true
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
    
    check_zfs_installed
    
    # If no pool specified, show list and select
    if [[ -z "$POOL_NAME" ]]; then
        if [[ "$JSON_OUTPUT" == "true" ]]; then
            die "Pool name required for JSON output"
        fi
        list_pools
    fi
    
    # Validate pool exists
    if ! pool_exists "$POOL_NAME"; then
        die "Pool '$POOL_NAME' does not exist"
    fi
    
    # Gather info
    get_pool_info "$POOL_NAME"
    
    # Output
    if [[ "$JSON_OUTPUT" == "true" ]]; then
        format_json_output "$POOL_NAME"
    else
        format_text_output "$POOL_NAME"
    fi
}

main "$@"
