#!/bin/bash
# zfs-pool-health.sh - Check ZFS pool health and provide recommendations
#
# Usage: zfs-pool-health.sh [POOL_NAME] [OPTIONS]
#
# Options:
#   -a, --all       Check all pools
#   -j, --json      Output as JSON
#   -l, --log FILE  Log to file
#   -q, --quiet     Only show problems (warnings/errors)
#   -h, --help      Show help

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

# =============================================================================
# DEFAULTS
# =============================================================================
POOL_NAME=""
CHECK_ALL=false

# Check results
declare -a CHECK_RESULTS=()
WARNINGS=0
ERRORS=0

# =============================================================================
# FUNCTIONS
# =============================================================================
show_help() {
    cat << 'EOF'
ZFS Pool Health Check - Check ZFS pool health and provide recommendations

Usage: zfs-pool-health.sh [POOL_NAME] [OPTIONS]

Options:
  -a, --all       Check all pools
  -j, --json      Output as JSON
  -l, --log FILE  Log to file
  -q, --quiet     Only show problems (warnings/errors)
  -h, --help      Show this help

Examples:
  # Interactive - select pool
  zfs-pool-health.sh

  # Check specific pool
  zfs-pool-health.sh default

  # Check all pools
  zfs-pool-health.sh --all

  # Output as JSON
  zfs-pool-health.sh default --json

Checks performed:
  - Pool status (ONLINE/DEGRADED/FAULTED)
  - Read/write/checksum errors
  - Last scrub time
  - Compression status
  - Dedup status and RAM usage
  - Capacity usage (warning at 80%)
  - Fragmentation level
  - Autotrim status
EOF
}

add_check_result() {
    local name="$1"
    local status="$2"  # ok, warn, error
    local value="$3"
    local recommendation="${4:-}"
    
    CHECK_RESULTS+=("$name|$status|$value|$recommendation")
    
    case "$status" in
        warn) ((WARNINGS++)) || true ;;
        error) ((ERRORS++)) || true ;;
    esac
}

format_check_line() {
    local status="$1"
    local message="$2"
    
    case "$status" in
        ok)
            if [[ "$QUIET" == "false" ]]; then
                echo -e "${GREEN}[OK]${NC}    $message"
            fi
            ;;
        warn)
            echo -e "${YELLOW}[WARN]${NC}  $message"
            ;;
        error)
            echo -e "${RED}[ERROR]${NC} $message"
            ;;
    esac
}

# =============================================================================
# HEALTH CHECKS
# =============================================================================
check_pool_status() {
    local pool="$1"
    local state health
    state=$(zpool list -H -o health "$pool")
    health=$(zpool get -H -o value health "$pool")
    
    case "$state" in
        ONLINE)
            add_check_result "pool_status" "ok" "$state"
            ;;
        DEGRADED)
            add_check_result "pool_status" "warn" "$state" "Pool is degraded. Check 'zpool status $pool' for details."
            ;;
        *)
            add_check_result "pool_status" "error" "$state" "Pool is $state! Immediate attention required."
            ;;
    esac
}

check_io_errors() {
    local pool="$1"
    local status_output
    status_output=$(zpool status "$pool")
    
    # Parse errors from status
    local read_errors write_errors cksum_errors
    read_errors=$(echo "$status_output" | grep -E '^\s+[a-zA-Z/]' | awk '{sum+=$3} END {print sum+0}')
    write_errors=$(echo "$status_output" | grep -E '^\s+[a-zA-Z/]' | awk '{sum+=$4} END {print sum+0}')
    cksum_errors=$(echo "$status_output" | grep -E '^\s+[a-zA-Z/]' | awk '{sum+=$5} END {print sum+0}')
    
    local total_errors=$((read_errors + write_errors + cksum_errors))
    local value="R:$read_errors W:$write_errors C:$cksum_errors"
    
    if [[ $total_errors -eq 0 ]]; then
        add_check_result "io_errors" "ok" "$value"
    elif [[ $cksum_errors -gt 0 ]]; then
        add_check_result "io_errors" "error" "$value" "Checksum errors detected! Data corruption possible. Run 'zpool scrub $pool'."
    else
        add_check_result "io_errors" "warn" "$value" "I/O errors detected. Monitor closely."
    fi
}

check_scrub_status() {
    local pool="$1"
    local status_output
    status_output=$(zpool status "$pool")
    
    if echo "$status_output" | grep -q "scrub in progress"; then
        local progress
        progress=$(echo "$status_output" | grep "done" | head -1)
        add_check_result "scrub" "ok" "in progress" "$progress"
        return
    fi
    
    local scrub_line
    scrub_line=$(echo "$status_output" | grep "scan:" | head -1)
    
    if echo "$scrub_line" | grep -q "scrub repaired"; then
        # Extract date - format varies
        local scrub_date
        scrub_date=$(echo "$scrub_line" | grep -oE '[A-Z][a-z]{2} +[0-9]+ +[0-9:]+' | head -1 || echo "")
        
        if [[ -n "$scrub_date" ]]; then
            # Check if scrub was more than 30 days ago
            local scrub_epoch now_epoch days_ago
            scrub_epoch=$(date -d "$scrub_date" +%s 2>/dev/null || echo 0)
            now_epoch=$(date +%s)
            
            if [[ $scrub_epoch -gt 0 ]]; then
                days_ago=$(( (now_epoch - scrub_epoch) / 86400 ))
                
                if [[ $days_ago -gt 30 ]]; then
                    add_check_result "scrub" "warn" "${days_ago} days ago" "Last scrub was $days_ago days ago. Recommend: 'zpool scrub $pool'"
                else
                    add_check_result "scrub" "ok" "${days_ago} days ago"
                fi
            else
                add_check_result "scrub" "ok" "$scrub_date"
            fi
        else
            add_check_result "scrub" "ok" "completed"
        fi
    elif echo "$scrub_line" | grep -q "none requested"; then
        add_check_result "scrub" "warn" "never" "No scrub has been performed. Recommend: 'zpool scrub $pool'"
    else
        add_check_result "scrub" "warn" "unknown" "Could not determine scrub status"
    fi
}

check_compression() {
    local pool="$1"
    local compression ratio
    compression=$(zfs get -H -o value compression "$pool")
    ratio=$(zfs get -H -o value compressratio "$pool")
    
    if [[ "$compression" == "off" ]]; then
        add_check_result "compression" "warn" "off (ratio: $ratio)" "Compression is disabled. Consider enabling: 'zfs set compression=zstd $pool'"
    else
        add_check_result "compression" "ok" "$compression (ratio: $ratio)"
    fi
}

check_dedup() {
    local pool="$1"
    local dedup dedup_ratio
    dedup=$(zfs get -H -o value dedup "$pool")
    dedup_ratio=$(zpool get -H -o value dedupratio "$pool")
    
    if [[ "$dedup" == "off" ]]; then
        add_check_result "dedup" "ok" "off"
        return
    fi
    
    # Get DDT size estimate
    local ddt_size=""
    local pool_size_bytes used_bytes
    pool_size_bytes=$(zpool get -H -o value -p size "$pool")
    used_bytes=$(zpool get -H -o value -p allocated "$pool")
    
    # Rough estimate: DDT uses ~320 bytes per block, average block ~128KB
    # So DDT size ≈ used_bytes / 128KB * 320 bytes = used_bytes * 0.0025
    local ddt_estimate=$((used_bytes * 25 / 10000))
    local ddt_human=$(format_size $ddt_estimate)
    
    # RAM estimate for dedup (5GB per 1TB)
    local ram_needed=$((used_bytes * 5 / 1024 / 1024 / 1024 / 1024 * 1024 * 1024 * 1024))
    if [[ $ram_needed -lt 1073741824 ]]; then
        ram_needed=1073741824  # minimum 1GB
    fi
    local ram_human=$(format_size $ram_needed)
    
    # Get available RAM
    local total_ram available_ram
    total_ram=$(grep MemTotal /proc/meminfo | awk '{print $2 * 1024}')
    available_ram=$(grep MemAvailable /proc/meminfo | awk '{print $2 * 1024}')
    
    local value="on (ratio: $dedup_ratio, DDT: ~$ddt_human)"
    
    if [[ $ram_needed -gt $available_ram ]]; then
        add_check_result "dedup" "warn" "$value" "Dedup may need ~$ram_human RAM. Available: $(format_size $available_ram)"
    else
        add_check_result "dedup" "ok" "$value"
    fi
}

check_capacity() {
    local pool="$1"
    local capacity
    capacity=$(zpool get -H -o value capacity "$pool")
    local cap_num="${capacity//%/}"
    
    if [[ $cap_num -ge 90 ]]; then
        add_check_result "capacity" "error" "$capacity" "Pool is $capacity full! Expand immediately or delete data."
    elif [[ $cap_num -ge 80 ]]; then
        add_check_result "capacity" "warn" "$capacity" "Pool is $capacity full. Consider expanding soon."
    else
        add_check_result "capacity" "ok" "$capacity"
    fi
}

check_fragmentation() {
    local pool="$1"
    local frag
    frag=$(zpool get -H -o value fragmentation "$pool")
    
    if [[ "$frag" == "-" ]]; then
        add_check_result "fragmentation" "ok" "N/A"
        return
    fi
    
    local frag_num="${frag//%/}"
    
    if [[ $frag_num -ge 70 ]]; then
        add_check_result "fragmentation" "warn" "$frag" "High fragmentation may impact performance"
    else
        add_check_result "fragmentation" "ok" "$frag"
    fi
}

check_autotrim() {
    local pool="$1"
    local autotrim backend_type
    autotrim=$(zpool get -H -o value autotrim "$pool")
    backend_type=$(get_pool_backend_type "$pool")
    
    if [[ "$autotrim" == "on" ]]; then
        add_check_result "autotrim" "ok" "on"
    elif [[ "$backend_type" == "file" ]]; then
        add_check_result "autotrim" "warn" "off" "Autotrim disabled. For sparse files, enable with: 'zpool set autotrim=on $pool'"
    else
        add_check_result "autotrim" "ok" "off (device backend)"
    fi
}

# =============================================================================
# OUTPUT FUNCTIONS
# =============================================================================
run_all_checks() {
    local pool="$1"
    CHECK_RESULTS=()
    WARNINGS=0
    ERRORS=0
    
    check_pool_status "$pool"
    check_io_errors "$pool"
    check_scrub_status "$pool"
    check_compression "$pool"
    check_dedup "$pool"
    check_capacity "$pool"
    check_fragmentation "$pool"
    check_autotrim "$pool"
}

format_text_output() {
    local pool="$1"
    
    header "ZFS Health Check: $pool"
    echo ""
    
    for result in "${CHECK_RESULTS[@]}"; do
        IFS='|' read -r name status value recommendation <<< "$result"
        
        local message
        case "$name" in
            pool_status) message="Pool status: $value" ;;
            io_errors) message="I/O errors: $value" ;;
            scrub) message="Last scrub: $value" ;;
            compression) message="Compression: $value" ;;
            dedup) message="Dedup: $value" ;;
            capacity) message="Capacity: $value" ;;
            fragmentation) message="Fragmentation: $value" ;;
            autotrim) message="Autotrim: $value" ;;
            *) message="$name: $value" ;;
        esac
        
        format_check_line "$status" "$message"
        
        if [[ -n "$recommendation" ]]; then
            echo -e "        ${CYAN}$recommendation${NC}"
        fi
    done
    
    echo ""
    echo "─────────────────────────────────────"
    
    local overall
    if [[ $ERRORS -gt 0 ]]; then
        overall="${RED}CRITICAL${NC}"
    elif [[ $WARNINGS -gt 0 ]]; then
        overall="${YELLOW}HEALTHY${NC} ($WARNINGS warnings)"
    else
        overall="${GREEN}HEALTHY${NC}"
    fi
    
    echo -e "Overall: $overall"
}

format_json_output() {
    local pool="$1"
    
    local overall="HEALTHY"
    if [[ $ERRORS -gt 0 ]]; then
        overall="CRITICAL"
    elif [[ $WARNINGS -gt 0 ]]; then
        overall="WARNING"
    fi
    
    echo "{"
    echo "  \"pool\": \"$pool\","
    echo "  \"overall\": \"$overall\","
    echo "  \"warnings\": $WARNINGS,"
    echo "  \"errors\": $ERRORS,"
    echo "  \"checks\": ["
    
    local first=true
    for result in "${CHECK_RESULTS[@]}"; do
        IFS='|' read -r name status value recommendation <<< "$result"
        
        if [[ "$first" == "true" ]]; then
            first=false
        else
            echo ","
        fi
        
        echo -n "    {\"name\": \"$name\", \"status\": \"$status\", \"value\": \"$value\""
        if [[ -n "$recommendation" ]]; then
            # Escape quotes in recommendation
            recommendation="${recommendation//\"/\\\"}"
            echo -n ", \"recommendation\": \"$recommendation\""
        fi
        echo -n "}"
    done
    
    echo ""
    echo "  ]"
    echo "}"
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
        local health
        health=$(zpool get -H -o value health "$pool")
        echo "  $i. $pool ($health)"
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

# =============================================================================
# ARGUMENT PARSING
# =============================================================================
parse_args() {
    parse_common_args "$@"
    set -- "${REMAINING_ARGS[@]}"
    
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -a|--all)
                CHECK_ALL=true
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
    
    local pools_to_check=()
    
    if [[ "$CHECK_ALL" == "true" ]]; then
        while IFS= read -r pool; do
            pools_to_check+=("$pool")
        done <<< "$(get_pools)"
        
        if [[ ${#pools_to_check[@]} -eq 0 ]]; then
            die "No ZFS pools found"
        fi
    elif [[ -z "$POOL_NAME" ]]; then
        if [[ "$JSON_OUTPUT" == "true" ]]; then
            die "Pool name required for JSON output (or use --all)"
        fi
        list_pools
        pools_to_check+=("$POOL_NAME")
    else
        if ! pool_exists "$POOL_NAME"; then
            die "Pool '$POOL_NAME' does not exist"
        fi
        pools_to_check+=("$POOL_NAME")
    fi
    
    # Check each pool
    local total_warnings=0
    local total_errors=0
    
    if [[ "$JSON_OUTPUT" == "true" && ${#pools_to_check[@]} -gt 1 ]]; then
        echo "["
    fi
    
    local first_pool=true
    for pool in "${pools_to_check[@]}"; do
        run_all_checks "$pool"
        ((total_warnings += WARNINGS)) || true
        ((total_errors += ERRORS)) || true
        
        if [[ "$JSON_OUTPUT" == "true" ]]; then
            if [[ "$first_pool" == "true" ]]; then
                first_pool=false
            else
                echo ","
            fi
            format_json_output "$pool"
        else
            format_text_output "$pool"
            if [[ ${#pools_to_check[@]} -gt 1 ]]; then
                echo ""
            fi
        fi
    done
    
    if [[ "$JSON_OUTPUT" == "true" && ${#pools_to_check[@]} -gt 1 ]]; then
        echo "]"
    fi
    
    # Exit code based on health
    if [[ $total_errors -gt 0 ]]; then
        exit 2
    elif [[ $total_warnings -gt 0 ]]; then
        exit 1
    fi
    exit 0
}

main "$@"
