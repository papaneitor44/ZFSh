#!/bin/bash
# zfs-pool-create.sh - Create ZFS pool on sparse file with configurable options
#
# Usage: zfs-pool-create.sh [OPTIONS]
#
# Options:
#   -n, --name NAME         Pool name (default: default)
#   -s, --size SIZE         Pool size, e.g. 50G, 100G (required)
#   -p, --path PATH         Path to image file (default: /var/lib/incus/disks/NAME.img)
#   -c, --compression TYPE  Compression: off, lz4, zstd (default: zstd)
#   -d, --dedup on|off      Enable deduplication (default: off)
#   -t, --trim on|off       Enable autotrim (default: on)
#   -y, --yes               Skip confirmation
#   -j, --json              Output as JSON
#   -l, --log [FILE]        Log to file (default: /var/log/zfsh.log)
#   -q, --quiet             Minimal output
#   -h, --help              Show help

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

# =============================================================================
# DEFAULTS
# =============================================================================
POOL_NAME="default"
POOL_SIZE=""
IMAGE_PATH=""
COMPRESSION="zstd"
DEDUP="off"
AUTOTRIM="on"
SKIP_CONFIRM=false

# =============================================================================
# FUNCTIONS
# =============================================================================
show_help() {
    cat << 'EOF'
ZFS Pool Create - Create ZFS pool on sparse file

Usage: zfs-pool-create.sh [OPTIONS]

Options:
  -n, --name NAME         Pool name (default: default)
  -s, --size SIZE         Pool size, e.g. 50G, 100G (required)
  -p, --path PATH         Path to image file (default: /var/lib/incus/disks/NAME.img)
  -c, --compression TYPE  Compression: off, lz4, zstd (default: zstd)
  -d, --dedup on|off      Enable deduplication (default: off)
  -t, --trim on|off       Enable autotrim (default: on)
  -y, --yes               Skip confirmation
  -j, --json              Output as JSON
  -l, --log [FILE]        Log to file
  -q, --quiet             Minimal output
  -h, --help              Show this help

Examples:
  # Interactive mode
  zfs-pool-create.sh

  # Create 50G pool with defaults
  zfs-pool-create.sh -s 50G -y

  # Create pool with custom settings
  zfs-pool-create.sh -n storage -s 100G -c zstd -d on -t on -y

  # Create pool and output JSON
  zfs-pool-create.sh -s 50G -y --json
EOF
}

validate_inputs() {
    # Pool name validation
    if [[ ! "$POOL_NAME" =~ ^[a-zA-Z][a-zA-Z0-9_-]*$ ]]; then
        die "Invalid pool name: $POOL_NAME (must start with letter, contain only letters, numbers, underscore, hyphen)"
    fi
    
    # Size validation
    if [[ -z "$POOL_SIZE" ]]; then
        die "Pool size is required"
    fi
    
    if [[ ! "$POOL_SIZE" =~ ^[0-9]+[GgMmTt]?[Bb]?$ ]]; then
        die "Invalid size format: $POOL_SIZE (use format like 50G, 100G, 1T)"
    fi
    
    # Compression validation
    case "$COMPRESSION" in
        off|lz4|zstd) ;;
        *) die "Invalid compression: $COMPRESSION (use: off, lz4, zstd)" ;;
    esac
    
    # Dedup validation
    case "$DEDUP" in
        on|off) ;;
        *) die "Invalid dedup value: $DEDUP (use: on, off)" ;;
    esac
    
    # Autotrim validation
    case "$AUTOTRIM" in
        on|off) ;;
        *) die "Invalid autotrim value: $AUTOTRIM (use: on, off)" ;;
    esac
    
    # Set default image path if not specified
    if [[ -z "$IMAGE_PATH" ]]; then
        IMAGE_PATH="/var/lib/incus/disks/${POOL_NAME}.img"
    fi
}

check_prerequisites() {
    check_root
    check_zfs_installed
    
    # Check if pool already exists
    if pool_exists "$POOL_NAME"; then
        die "Pool '$POOL_NAME' already exists"
    fi
    
    # Check if image file already exists
    if [[ -f "$IMAGE_PATH" ]]; then
        die "Image file already exists: $IMAGE_PATH"
    fi
    
    # Check free space
    local size_bytes
    size_bytes=$(parse_size "$POOL_SIZE")
    local free_bytes
    free_bytes=$(get_free_space "$(dirname "$IMAGE_PATH")")
    
    if [[ $size_bytes -gt $free_bytes ]]; then
        die "Not enough free space. Required: $(format_size $size_bytes), Available: $(format_size $free_bytes)"
    fi
}

show_summary() {
    if [[ "$JSON_OUTPUT" == "false" && "$QUIET" == "false" ]]; then
        echo ""
        echo "Summary:"
        echo "  Pool name:    $POOL_NAME"
        echo "  Size:         $POOL_SIZE"
        echo "  Image path:   $IMAGE_PATH"
        echo "  Compression:  $COMPRESSION"
        echo "  Dedup:        $DEDUP"
        echo "  Autotrim:     $AUTOTRIM"
        echo ""
    fi
}

create_pool() {
    local image_dir
    image_dir="$(dirname "$IMAGE_PATH")"
    
    # Create directory if needed
    if [[ ! -d "$image_dir" ]]; then
        info "Creating directory: $image_dir"
        mkdir -p "$image_dir"
    fi
    
    # Create sparse file
    info "Creating sparse file: $IMAGE_PATH ($POOL_SIZE)"
    truncate -s "$POOL_SIZE" "$IMAGE_PATH"
    
    # Create zpool
    info "Creating ZFS pool: $POOL_NAME"
    zpool create -o autotrim="$AUTOTRIM" "$POOL_NAME" "$IMAGE_PATH"
    
    # Set compression
    if [[ "$COMPRESSION" != "off" ]]; then
        info "Setting compression: $COMPRESSION"
        zfs set compression="$COMPRESSION" "$POOL_NAME"
    fi
    
    # Set dedup
    if [[ "$DEDUP" == "on" ]]; then
        info "Enabling deduplication"
        zfs set dedup=on "$POOL_NAME"
    fi
    
    success "Pool '$POOL_NAME' created successfully"
}

output_result() {
    if [[ "$JSON_OUTPUT" == "true" ]]; then
        local total_bytes used_bytes free_bytes
        total_bytes=$(zpool get -H -o value -p size "$POOL_NAME")
        used_bytes=$(zpool get -H -o value -p allocated "$POOL_NAME")
        free_bytes=$(zpool get -H -o value -p free "$POOL_NAME")
        
        cat << EOF
{
  "success": true,
  "pool": {
    "name": "$POOL_NAME",
    "size": "$POOL_SIZE",
    "path": "$IMAGE_PATH",
    "compression": "$COMPRESSION",
    "dedup": "$DEDUP",
    "autotrim": "$AUTOTRIM"
  },
  "storage": {
    "total": $total_bytes,
    "used": $used_bytes,
    "free": $free_bytes
  }
}
EOF
    fi
}

interactive_mode() {
    header "ZFS Pool Creation"
    
    prompt "Pool name" "$POOL_NAME"
    POOL_NAME="$REPLY"
    
    while [[ -z "$POOL_SIZE" ]]; do
        prompt "Pool size (e.g. 50G, 100G)" ""
        POOL_SIZE="$REPLY"
    done
    
    local default_path="/var/lib/incus/disks/${POOL_NAME}.img"
    prompt "Image path" "$default_path"
    IMAGE_PATH="$REPLY"
    
    prompt_select "Compression" "zstd (recommended)" "lz4" "off"
    case "$REPLY" in
        "zstd (recommended)") COMPRESSION="zstd" ;;
        "lz4") COMPRESSION="lz4" ;;
        "off") COMPRESSION="off" ;;
    esac
    
    if prompt_yn "Enable deduplication?" "n"; then
        DEDUP="on"
        warn "Dedup requires ~5GB RAM per 1TB of data"
    else
        DEDUP="off"
    fi
    
    if prompt_yn "Enable autotrim?" "y"; then
        AUTOTRIM="on"
    else
        AUTOTRIM="off"
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
            -n|--name)
                POOL_NAME="$2"
                shift 2
                ;;
            -s|--size)
                POOL_SIZE="$2"
                shift 2
                ;;
            -p|--path)
                IMAGE_PATH="$2"
                shift 2
                ;;
            -c|--compression)
                COMPRESSION="$2"
                shift 2
                ;;
            -d|--dedup)
                DEDUP="$2"
                shift 2
                ;;
            -t|--trim)
                AUTOTRIM="$2"
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
            *)
                die "Unknown option: $1 (use -h for help)"
                ;;
        esac
    done
}

# =============================================================================
# MAIN
# =============================================================================
main() {
    parse_args "$@"
    
    # Interactive mode if size not provided
    if [[ -z "$POOL_SIZE" ]]; then
        interactive_mode
    fi
    
    validate_inputs
    check_prerequisites
    show_summary
    
    # Confirm unless -y
    if [[ "$SKIP_CONFIRM" == "false" ]]; then
        if ! confirm "Create pool?"; then
            echo "Aborted."
            exit 0
        fi
    fi
    
    create_pool
    output_result
}

main "$@"
