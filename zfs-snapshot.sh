#!/bin/bash
# zfs-snapshot.sh - Manage ZFS snapshots
#
# Usage: zfs-snapshot.sh <command> [options]
#
# Commands:
#   create     Create snapshot
#   list       List snapshots
#   delete     Delete snapshots
#   rollback   Rollback to snapshot
#   cleanup    Apply retention policy

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

# =============================================================================
# DEFAULTS
# =============================================================================
RECURSIVE=false
SKIP_CONFIRM=false
DRY_RUN=false
SNAPSHOT_NAME=""
PREFIX_FILTER=""
AGE_FILTER=""
KEEP_LAST=0
KEEP_DAILY=0
KEEP_WEEKLY=0
KEEP_MONTHLY=0
OLDER_THAN=""
FORCE=false

# =============================================================================
# HELP
# =============================================================================
show_help() {
    cat << 'EOF'
ZFS Snapshot Manager - Manage ZFS snapshots

Usage: zfs-snapshot.sh <command> [options]

Commands:
  create     Create snapshot
  list       List snapshots
  delete     Delete snapshots
  rollback   Rollback to snapshot
  cleanup    Apply retention policy

Global Options:
  -j, --json      Output as JSON
  -l, --log FILE  Log to file
  -q, --quiet     Minimal output
  -h, --help      Show this help

Examples:
  zfs-snapshot.sh create default/data
  zfs-snapshot.sh create default -r --prefix daily
  zfs-snapshot.sh list --pool default
  zfs-snapshot.sh cleanup default --keep-daily 7 --keep-weekly 4
  zfs-snapshot.sh delete default --older-than 30d

Use 'zfs-snapshot.sh <command> --help' for command-specific help.
EOF
}

show_create_help() {
    cat << 'EOF'
Create ZFS snapshot

Usage: zfs-snapshot.sh create <dataset> [options]

Options:
  -n, --name NAME       Snapshot name (default: auto-generated)
  -r, --recursive       Create recursive snapshots
  -p, --prefix PREFIX   Name prefix (default: backup)
  -y, --yes             Skip confirmation

Examples:
  zfs-snapshot.sh create default/containers/web
  zfs-snapshot.sh create default -r --prefix hourly
  zfs-snapshot.sh create default/data -n before-upgrade
EOF
}

show_list_help() {
    cat << 'EOF'
List ZFS snapshots

Usage: zfs-snapshot.sh list [dataset] [options]

Options:
  -p, --pool POOL       Filter by pool
  -a, --age AGE         Filter by max age (e.g., 7d, 2w)
  --prefix PREFIX       Filter by name prefix
  --sort FIELD          Sort by: creation, name, used (default: creation)

Examples:
  zfs-snapshot.sh list
  zfs-snapshot.sh list default/containers
  zfs-snapshot.sh list --pool default --age 7d
  zfs-snapshot.sh list --prefix backup --json
EOF
}

show_delete_help() {
    cat << 'EOF'
Delete ZFS snapshots

Usage: zfs-snapshot.sh delete <dataset|snapshot> [options]

Options:
  -n, --name NAME       Delete specific snapshot by name
  -r, --recursive       Delete recursively
  --older-than AGE      Delete snapshots older than AGE
  --prefix PREFIX       Delete only with this prefix
  --dry-run             Show what would be deleted
  -y, --yes             Skip confirmation

Examples:
  zfs-snapshot.sh delete default/data@backup_20240101
  zfs-snapshot.sh delete default --older-than 30d --prefix backup
  zfs-snapshot.sh delete default -r --older-than 7d --dry-run
EOF
}

show_rollback_help() {
    cat << 'EOF'
Rollback dataset to snapshot

Usage: zfs-snapshot.sh rollback <snapshot> [options]

Options:
  -r, --recursive       Rollback children too
  -f, --force           Destroy intermediate snapshots
  -y, --yes             Skip confirmation

Examples:
  zfs-snapshot.sh rollback default/data@before-upgrade
  zfs-snapshot.sh rollback default/web@backup_20240101 -f
EOF
}

show_cleanup_help() {
    cat << 'EOF'
Cleanup snapshots using retention policy

Usage: zfs-snapshot.sh cleanup <dataset> [options]

Retention Options:
  --keep-last N         Keep last N snapshots
  --keep-daily N        Keep N daily snapshots (one per day)
  --keep-weekly N       Keep N weekly snapshots (one per week)
  --keep-monthly N      Keep N monthly snapshots (one per month)
  --older-than AGE      Delete older than AGE (e.g., 90d)

Other Options:
  -r, --recursive       Apply to children
  --prefix PREFIX       Apply only to snapshots with prefix
  --dry-run             Show what would be deleted
  -y, --yes             Skip confirmation

Examples:
  zfs-snapshot.sh cleanup default --keep-last 10
  zfs-snapshot.sh cleanup default --keep-daily 7 --keep-weekly 4 --keep-monthly 3
  zfs-snapshot.sh cleanup default --older-than 90d --dry-run
EOF
}

# =============================================================================
# COMMANDS
# =============================================================================

cmd_create() {
    local dataset=""
    
    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -n|--name)
                SNAPSHOT_NAME="$2"
                shift 2
                ;;
            -r|--recursive)
                RECURSIVE=true
                shift
                ;;
            -p|--prefix)
                SNAPSHOT_PREFIX="$2"
                shift 2
                ;;
            -y|--yes)
                SKIP_CONFIRM=true
                shift
                ;;
            -h|--help)
                show_create_help
                exit 0
                ;;
            -*)
                die "Unknown option: $1"
                ;;
            *)
                dataset="$1"
                shift
                ;;
        esac
    done
    
    [[ -z "$dataset" ]] && die "Dataset required. Use -h for help."
    
    check_root
    check_zfs_installed
    
    if ! dataset_exists "$dataset"; then
        die "Dataset '$dataset' does not exist"
    fi
    
    # Generate snapshot name if not provided
    if [[ -z "$SNAPSHOT_NAME" ]]; then
        SNAPSHOT_NAME=$(generate_snapshot_name "$SNAPSHOT_PREFIX")
    fi
    
    local snapshot="${dataset}@${SNAPSHOT_NAME}"
    
    info "Creating snapshot: $snapshot"
    
    local zfs_opts=""
    [[ "$RECURSIVE" == "true" ]] && zfs_opts="-r"
    
    if zfs snapshot $zfs_opts "$snapshot"; then
        success "Snapshot created: $snapshot"
        
        if [[ "$JSON_OUTPUT" == "true" ]]; then
            local creation used
            creation=$(zfs get -H -o value creation "$snapshot")
            used=$(zfs get -H -o value used "$snapshot")
            cat << EOF
{"success": true, "snapshot": "$snapshot", "creation": "$creation", "used": "$used", "recursive": $RECURSIVE}
EOF
        fi
    else
        die "Failed to create snapshot"
    fi
}

cmd_list() {
    local dataset=""
    local pool_filter=""
    local sort_field="creation"
    
    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -p|--pool)
                pool_filter="$2"
                shift 2
                ;;
            -a|--age)
                AGE_FILTER="$2"
                shift 2
                ;;
            --prefix)
                PREFIX_FILTER="$2"
                shift 2
                ;;
            --sort)
                sort_field="$2"
                shift 2
                ;;
            -h|--help)
                show_list_help
                exit 0
                ;;
            -*)
                die "Unknown option: $1"
                ;;
            *)
                dataset="$1"
                shift
                ;;
        esac
    done
    
    check_zfs_installed
    
    # Build zfs list command
    local zfs_cmd="zfs list -t snapshot -H -o name,creation,used,refer"
    
    case "$sort_field" in
        creation) zfs_cmd+=" -s creation" ;;
        name)     zfs_cmd+=" -s name" ;;
        used)     zfs_cmd+=" -s used" ;;
    esac
    
    local snapshots
    snapshots=$($zfs_cmd 2>/dev/null) || true
    
    # Filter by dataset/pool
    if [[ -n "$dataset" ]]; then
        snapshots=$(echo "$snapshots" | grep "^${dataset}@" || true)
    elif [[ -n "$pool_filter" ]]; then
        snapshots=$(echo "$snapshots" | grep "^${pool_filter}" || true)
    fi
    
    # Filter by prefix
    if [[ -n "$PREFIX_FILTER" ]]; then
        snapshots=$(echo "$snapshots" | grep "@${PREFIX_FILTER}" || true)
    fi
    
    # Filter by age
    if [[ -n "$AGE_FILTER" ]]; then
        local max_age_seconds
        max_age_seconds=$(parse_age "$AGE_FILTER")
        local now
        now=$(date +%s)
        local filtered=""
        
        while IFS=$'\t' read -r name creation used refer; do
            [[ -z "$name" ]] && continue
            local snap_epoch
            snap_epoch=$(date -d "$creation" +%s 2>/dev/null || echo "0")
            local age=$((now - snap_epoch))
            if [[ $age -le $max_age_seconds ]]; then
                filtered+="${name}\t${creation}\t${used}\t${refer}\n"
            fi
        done <<< "$snapshots"
        snapshots=$(echo -e "$filtered")
    fi
    
    if [[ -z "$snapshots" ]]; then
        if [[ "$JSON_OUTPUT" == "true" ]]; then
            echo '{"snapshots": []}'
        else
            info "No snapshots found"
        fi
        return 0
    fi
    
    if [[ "$JSON_OUTPUT" == "true" ]]; then
        echo '{"snapshots": ['
        local first=true
        while IFS=$'\t' read -r name creation used refer; do
            [[ -z "$name" ]] && continue
            [[ "$first" == "true" ]] && first=false || echo ","
            echo -n "{\"name\": \"$name\", \"creation\": \"$creation\", \"used\": \"$used\", \"refer\": \"$refer\"}"
        done <<< "$snapshots"
        echo ']}'
    else
        echo ""
        printf "%-50s %-20s %-10s %-10s\n" "NAME" "CREATION" "USED" "REFER"
        printf "%-50s %-20s %-10s %-10s\n" "----" "--------" "----" "-----"
        while IFS=$'\t' read -r name creation used refer; do
            [[ -z "$name" ]] && continue
            printf "%-50s %-20s %-10s %-10s\n" "$name" "$creation" "$used" "$refer"
        done <<< "$snapshots"
    fi
}

cmd_delete() {
    local target=""
    local snapshots_to_delete=()
    
    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -n|--name)
                SNAPSHOT_NAME="$2"
                shift 2
                ;;
            -r|--recursive)
                RECURSIVE=true
                shift
                ;;
            --older-than)
                OLDER_THAN="$2"
                shift 2
                ;;
            --prefix)
                PREFIX_FILTER="$2"
                shift 2
                ;;
            --dry-run)
                DRY_RUN=true
                shift
                ;;
            -y|--yes)
                SKIP_CONFIRM=true
                shift
                ;;
            -h|--help)
                show_delete_help
                exit 0
                ;;
            -*)
                die "Unknown option: $1"
                ;;
            *)
                target="$1"
                shift
                ;;
        esac
    done
    
    [[ -z "$target" ]] && die "Target required. Use -h for help."
    
    check_root
    check_zfs_installed
    
    # Determine what to delete
    if [[ "$target" == *@* ]]; then
        # Direct snapshot reference
        if snapshot_exists "$target"; then
            snapshots_to_delete+=("$target")
        else
            die "Snapshot '$target' does not exist"
        fi
    else
        # Dataset - find matching snapshots
        local dataset="$target"
        
        if ! dataset_exists "$dataset"; then
            die "Dataset '$dataset' does not exist"
        fi
        
        local all_snapshots
        if [[ -n "$PREFIX_FILTER" ]]; then
            all_snapshots=$(get_snapshots "$dataset" "$PREFIX_FILTER")
        else
            all_snapshots=$(get_snapshots "$dataset")
        fi
        
        if [[ -n "$SNAPSHOT_NAME" ]]; then
            # Delete by specific name
            local snap="${dataset}@${SNAPSHOT_NAME}"
            if snapshot_exists "$snap"; then
                snapshots_to_delete+=("$snap")
            else
                die "Snapshot '$snap' does not exist"
            fi
        elif [[ -n "$OLDER_THAN" ]]; then
            # Delete by age
            local max_age_seconds
            max_age_seconds=$(parse_age "$OLDER_THAN")
            
            while IFS= read -r snap; do
                [[ -z "$snap" ]] && continue
                local age
                age=$(get_snapshot_age "$snap")
                if [[ $age -gt $max_age_seconds ]]; then
                    snapshots_to_delete+=("$snap")
                fi
            done <<< "$all_snapshots"
        else
            die "Specify --name, --older-than, or use full snapshot path"
        fi
    fi
    
    if [[ ${#snapshots_to_delete[@]} -eq 0 ]]; then
        info "No snapshots to delete"
        return 0
    fi
    
    # Show what will be deleted
    echo "Snapshots to delete (${#snapshots_to_delete[@]}):"
    for snap in "${snapshots_to_delete[@]}"; do
        echo "  $snap"
    done
    
    if [[ "$DRY_RUN" == "true" ]]; then
        info "Dry run - no changes made"
        return 0
    fi
    
    # Confirm
    if [[ "$SKIP_CONFIRM" == "false" ]]; then
        if ! confirm "Delete ${#snapshots_to_delete[@]} snapshot(s)?"; then
            echo "Aborted."
            return 0
        fi
    fi
    
    # Delete snapshots
    local deleted=0
    local failed=0
    local zfs_opts=""
    [[ "$RECURSIVE" == "true" ]] && zfs_opts="-r"
    
    for snap in "${snapshots_to_delete[@]}"; do
        if zfs destroy $zfs_opts "$snap" 2>/dev/null; then
            success "Deleted: $snap"
            ((deleted++))
        else
            error "Failed to delete: $snap"
            ((failed++))
        fi
    done
    
    if [[ "$JSON_OUTPUT" == "true" ]]; then
        echo "{\"deleted\": $deleted, \"failed\": $failed}"
    else
        info "Deleted: $deleted, Failed: $failed"
    fi
}

cmd_rollback() {
    local snapshot=""
    
    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -r|--recursive)
                RECURSIVE=true
                shift
                ;;
            -f|--force)
                FORCE=true
                shift
                ;;
            -y|--yes)
                SKIP_CONFIRM=true
                shift
                ;;
            -h|--help)
                show_rollback_help
                exit 0
                ;;
            -*)
                die "Unknown option: $1"
                ;;
            *)
                snapshot="$1"
                shift
                ;;
        esac
    done
    
    [[ -z "$snapshot" ]] && die "Snapshot required. Use -h for help."
    
    check_root
    check_zfs_installed
    
    if ! snapshot_exists "$snapshot"; then
        die "Snapshot '$snapshot' does not exist"
    fi
    
    local dataset="${snapshot%@*}"
    local snap_name="${snapshot#*@}"
    
    # Check for intermediate snapshots
    local newer_snapshots
    newer_snapshots=$(zfs list -t snapshot -H -o name -s creation "$dataset" 2>/dev/null | \
        awk -v target="$snapshot" 'found {print} $0 == target {found=1}' || true)
    
    if [[ -n "$newer_snapshots" && "$FORCE" == "false" ]]; then
        echo "Warning: The following snapshots are newer and will be destroyed:"
        echo "$newer_snapshots"
        echo ""
        warn "Use -f/--force to destroy intermediate snapshots"
        
        if [[ "$SKIP_CONFIRM" == "false" ]]; then
            if ! confirm "Continue anyway?"; then
                echo "Aborted."
                return 0
            fi
        fi
    fi
    
    info "Rolling back to: $snapshot"
    
    local zfs_opts=""
    [[ "$RECURSIVE" == "true" ]] && zfs_opts+=" -r"
    [[ "$FORCE" == "true" ]] && zfs_opts+=" -Rf"
    
    if zfs rollback $zfs_opts "$snapshot"; then
        success "Rollback complete"
        
        if [[ "$JSON_OUTPUT" == "true" ]]; then
            echo "{\"success\": true, \"snapshot\": \"$snapshot\"}"
        fi
    else
        die "Rollback failed"
    fi
}

cmd_cleanup() {
    local dataset=""
    
    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --keep-last)
                KEEP_LAST="$2"
                shift 2
                ;;
            --keep-daily)
                KEEP_DAILY="$2"
                shift 2
                ;;
            --keep-weekly)
                KEEP_WEEKLY="$2"
                shift 2
                ;;
            --keep-monthly)
                KEEP_MONTHLY="$2"
                shift 2
                ;;
            --older-than)
                OLDER_THAN="$2"
                shift 2
                ;;
            -r|--recursive)
                RECURSIVE=true
                shift
                ;;
            --prefix)
                PREFIX_FILTER="$2"
                shift 2
                ;;
            --dry-run)
                DRY_RUN=true
                shift
                ;;
            -y|--yes)
                SKIP_CONFIRM=true
                shift
                ;;
            -h|--help)
                show_cleanup_help
                exit 0
                ;;
            -*)
                die "Unknown option: $1"
                ;;
            *)
                dataset="$1"
                shift
                ;;
        esac
    done
    
    [[ -z "$dataset" ]] && die "Dataset required. Use -h for help."
    
    # Must have at least one retention option
    if [[ $KEEP_LAST -eq 0 && $KEEP_DAILY -eq 0 && $KEEP_WEEKLY -eq 0 && \
          $KEEP_MONTHLY -eq 0 && -z "$OLDER_THAN" ]]; then
        die "At least one retention option required (--keep-*, --older-than)"
    fi
    
    check_root
    check_zfs_installed
    
    if ! dataset_exists "$dataset"; then
        die "Dataset '$dataset' does not exist"
    fi
    
    # Get datasets to process
    local datasets=()
    if [[ "$RECURSIVE" == "true" ]]; then
        while IFS= read -r ds; do
            datasets+=("$ds")
        done < <(zfs list -H -o name -r "$dataset" 2>/dev/null)
    else
        datasets+=("$dataset")
    fi
    
    local total_delete=0
    local all_to_delete=()
    
    for ds in "${datasets[@]}"; do
        # Get snapshots for this dataset
        local snapshots_list
        if [[ -n "$PREFIX_FILTER" ]]; then
            snapshots_list=$(get_snapshots "$ds" "$PREFIX_FILTER")
        else
            snapshots_list=$(get_snapshots "$ds")
        fi
        
        [[ -z "$snapshots_list" ]] && continue
        
        # Convert to array
        local -a snapshots_array=()
        while IFS= read -r snap; do
            [[ -n "$snap" ]] && snapshots_array+=("$snap")
        done <<< "$snapshots_list"
        
        [[ ${#snapshots_array[@]} -eq 0 ]] && continue
        
        # Apply retention policy
        if [[ -n "$OLDER_THAN" ]]; then
            # Simple age-based deletion
            local max_age_seconds
            max_age_seconds=$(parse_age "$OLDER_THAN")
            
            for snap in "${snapshots_array[@]}"; do
                local age
                age=$(get_snapshot_age "$snap")
                if [[ $age -gt $max_age_seconds ]]; then
                    all_to_delete+=("$snap")
                fi
            done
        else
            # GFS retention policy
            apply_gfs_retention snapshots_array "$KEEP_LAST" "$KEEP_DAILY" "$KEEP_WEEKLY" "$KEEP_MONTHLY"
            
            for snap in "${RETENTION_DELETE[@]}"; do
                all_to_delete+=("$snap")
            done
        fi
    done
    
    if [[ ${#all_to_delete[@]} -eq 0 ]]; then
        info "No snapshots to delete based on retention policy"
        return 0
    fi
    
    # Show what will be deleted
    header "Cleanup Plan"
    echo "Retention policy:"
    [[ $KEEP_LAST -gt 0 ]] && echo "  Keep last: $KEEP_LAST"
    [[ $KEEP_DAILY -gt 0 ]] && echo "  Keep daily: $KEEP_DAILY"
    [[ $KEEP_WEEKLY -gt 0 ]] && echo "  Keep weekly: $KEEP_WEEKLY"
    [[ $KEEP_MONTHLY -gt 0 ]] && echo "  Keep monthly: $KEEP_MONTHLY"
    [[ -n "$OLDER_THAN" ]] && echo "  Older than: $OLDER_THAN"
    echo ""
    echo "Snapshots to delete (${#all_to_delete[@]}):"
    for snap in "${all_to_delete[@]}"; do
        local age
        age=$(format_age "$(get_snapshot_age "$snap")")
        echo "  $snap (age: $age)"
    done
    
    if [[ "$DRY_RUN" == "true" ]]; then
        info "Dry run - no changes made"
        return 0
    fi
    
    # Confirm
    if [[ "$SKIP_CONFIRM" == "false" ]]; then
        echo ""
        if ! confirm "Delete ${#all_to_delete[@]} snapshot(s)?"; then
            echo "Aborted."
            return 0
        fi
    fi
    
    # Delete
    local deleted=0
    local failed=0
    
    for snap in "${all_to_delete[@]}"; do
        if zfs destroy "$snap" 2>/dev/null; then
            success "Deleted: $snap"
            ((deleted++))
        else
            error "Failed to delete: $snap"
            ((failed++))
        fi
    done
    
    if [[ "$JSON_OUTPUT" == "true" ]]; then
        echo "{\"deleted\": $deleted, \"failed\": $failed, \"kept\": ${#RETENTION_KEEP[@]}}"
    else
        echo ""
        info "Summary: Deleted $deleted, Failed $failed"
    fi
}

# =============================================================================
# MAIN
# =============================================================================
main() {
    # Parse global options first
    parse_common_args "$@"
    set -- "${REMAINING_ARGS[@]}"
    
    if [[ $# -eq 0 ]]; then
        show_help
        exit 0
    fi
    
    local command="$1"
    shift
    
    case "$command" in
        create)   cmd_create "$@" ;;
        list)     cmd_list "$@" ;;
        delete)   cmd_delete "$@" ;;
        rollback) cmd_rollback "$@" ;;
        cleanup)  cmd_cleanup "$@" ;;
        -h|--help|help) show_help ;;
        *)        die "Unknown command: $command. Use -h for help." ;;
    esac
}

main "$@"
