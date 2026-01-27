#!/bin/bash
# zfs-cron-setup.sh - Manage scheduled ZFS tasks
#
# Usage: zfs-cron-setup.sh <command> [options]
#
# Commands:
#   add       Add scheduled task
#   list      List scheduled tasks
#   remove    Remove task
#   test      Test run task

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

# =============================================================================
# DEFAULTS
# =============================================================================
TASK_TYPE=""
POOL=""
DATASET=""
FREQUENCY="daily"
HOUR="2"
MINUTE="0"
CRON_EXPR=""
COMPRESS_TYPE="zstd"
BACKUP_DIR="/root/backups"
REMOTE_DEST=""
KEEP_LAST=0
KEEP_DAILY=0
KEEP_WEEKLY=0
KEEP_MONTHLY=0

# =============================================================================
# HELP
# =============================================================================
show_help() {
    cat << 'EOF'
ZFS Cron Setup - Manage scheduled ZFS tasks

Usage: zfs-cron-setup.sh <command> [options]

Commands:
  add       Add scheduled task
  list      List scheduled tasks
  remove    Remove task by ID
  test      Test run a task

Global Options:
  -j, --json      Output as JSON
  -l, --log FILE  Log to file
  -q, --quiet     Minimal output
  -h, --help      Show this help

Examples:
  zfs-cron-setup.sh add --type snapshot --pool default --daily
  zfs-cron-setup.sh add --type backup --pool default --weekly --compress zstd
  zfs-cron-setup.sh add --type cleanup --pool default --keep-daily 7 --keep-weekly 4
  zfs-cron-setup.sh list
  zfs-cron-setup.sh remove --id 3

Use 'zfs-cron-setup.sh <command> --help' for command-specific help.
EOF
}

show_add_help() {
    cat << 'EOF'
Add scheduled ZFS task

Usage: zfs-cron-setup.sh add [options]

Required:
  --type TYPE           Task type: snapshot, backup, cleanup, scrub

Target:
  --pool POOL           Target pool (required)
  --dataset DATASET     Target dataset (optional, defaults to pool)

Schedule:
  --hourly              Run hourly
  --daily               Run daily at specified time (default)
  --weekly              Run weekly on Sunday
  --monthly             Run monthly on 1st
  --cron "EXPR"         Custom cron expression (e.g., "0 */6 * * *")
  --time HH:MM          Time to run (default: 02:00)

Backup options (--type backup):
  --backup-dir PATH     Backup directory (default: /root/backups)
  --compress TYPE       Compression: gzip, zstd, lz4, none (default: zstd)
  --remote DEST         Remote destination (user@host:path)

Retention options (--type cleanup):
  --keep-last N         Keep last N
  --keep-daily N        Keep N daily
  --keep-weekly N       Keep N weekly
  --keep-monthly N      Keep N monthly

Examples:
  # Daily snapshots at 02:00
  zfs-cron-setup.sh add --type snapshot --pool default --daily

  # Cleanup with GFS retention
  zfs-cron-setup.sh add --type cleanup --pool default --daily \
      --keep-daily 7 --keep-weekly 4 --keep-monthly 3

  # Weekly backup to remote
  zfs-cron-setup.sh add --type backup --pool default --weekly \
      --remote backup@server:tank/backups

  # Monthly scrub
  zfs-cron-setup.sh add --type scrub --pool default --monthly
EOF
}

show_list_help() {
    cat << 'EOF'
List scheduled ZFS tasks

Usage: zfs-cron-setup.sh list [options]

Options:
  --type TYPE           Filter by task type

Examples:
  zfs-cron-setup.sh list
  zfs-cron-setup.sh list --type backup
  zfs-cron-setup.sh list --json
EOF
}

show_remove_help() {
    cat << 'EOF'
Remove scheduled ZFS task

Usage: zfs-cron-setup.sh remove [options]

Options:
  --id ID               Remove task by ID
  --type TYPE           Remove all tasks of type
  --pool POOL           Remove all tasks for pool
  --all                 Remove all ZFSh tasks (with confirmation)

Examples:
  zfs-cron-setup.sh remove --id 3
  zfs-cron-setup.sh remove --type snapshot --pool default
  zfs-cron-setup.sh remove --all
EOF
}

show_test_help() {
    cat << 'EOF'
Test run a scheduled task

Usage: zfs-cron-setup.sh test --id ID [options]

Options:
  --id ID               Task ID to test
  --dry-run             Show command without executing

Examples:
  zfs-cron-setup.sh test --id 1
  zfs-cron-setup.sh test --id 2 --dry-run
EOF
}

# =============================================================================
# COMMANDS
# =============================================================================

cmd_add() {
    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --type)
                TASK_TYPE="$2"
                shift 2
                ;;
            --pool)
                POOL="$2"
                shift 2
                ;;
            --dataset)
                DATASET="$2"
                shift 2
                ;;
            --hourly)
                FREQUENCY="hourly"
                shift
                ;;
            --daily)
                FREQUENCY="daily"
                shift
                ;;
            --weekly)
                FREQUENCY="weekly"
                shift
                ;;
            --monthly)
                FREQUENCY="monthly"
                shift
                ;;
            --cron)
                CRON_EXPR="$2"
                shift 2
                ;;
            --time)
                IFS=':' read -r HOUR MINUTE <<< "$2"
                shift 2
                ;;
            --backup-dir)
                BACKUP_DIR="$2"
                shift 2
                ;;
            --compress)
                COMPRESS_TYPE="$2"
                shift 2
                ;;
            --remote)
                REMOTE_DEST="$2"
                shift 2
                ;;
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
            -h|--help)
                show_add_help
                exit 0
                ;;
            -*)
                die "Unknown option: $1"
                ;;
            *)
                shift
                ;;
        esac
    done
    
    # Validate
    [[ -z "$TASK_TYPE" ]] && die "Task type required (--type)"
    [[ -z "$POOL" ]] && die "Pool required (--pool)"
    
    case "$TASK_TYPE" in
        snapshot|backup|cleanup|scrub) ;;
        *) die "Invalid task type: $TASK_TYPE (use: snapshot, backup, cleanup, scrub)" ;;
    esac
    
    check_root
    check_zfs_installed
    
    if ! pool_exists "$POOL"; then
        die "Pool '$POOL' does not exist"
    fi
    
    # Target dataset defaults to pool
    local target="${DATASET:-$POOL}"
    
    # Build schedule
    local schedule
    if [[ -n "$CRON_EXPR" ]]; then
        schedule="$CRON_EXPR"
    else
        schedule=$(build_cron_schedule "$FREQUENCY" "$HOUR" "$MINUTE")
    fi
    
    # Build command
    local cmd=""
    local extra_meta=""
    
    case "$TASK_TYPE" in
        snapshot)
            cmd="$SCRIPT_DIR/zfs-snapshot.sh create $target -r --prefix backup -q"
            ;;
        backup)
            cmd="$SCRIPT_DIR/zfs-backup.sh create $target"
            cmd+=" -o $BACKUP_DIR -c $COMPRESS_TYPE -q"
            extra_meta="backup-dir=${BACKUP_DIR}:compress=${COMPRESS_TYPE}"
            
            if [[ -n "$REMOTE_DEST" ]]; then
                # Use send instead of create for remote
                cmd="$SCRIPT_DIR/zfs-backup.sh send $target $REMOTE_DEST"
                cmd+=" -c $COMPRESS_TYPE -q"
                extra_meta="remote=${REMOTE_DEST}:compress=${COMPRESS_TYPE}"
            fi
            ;;
        cleanup)
            cmd="$SCRIPT_DIR/zfs-snapshot.sh cleanup $target -y -q"
            
            local retention_opts=""
            [[ $KEEP_LAST -gt 0 ]] && retention_opts+=" --keep-last $KEEP_LAST"
            [[ $KEEP_DAILY -gt 0 ]] && retention_opts+=" --keep-daily $KEEP_DAILY"
            [[ $KEEP_WEEKLY -gt 0 ]] && retention_opts+=" --keep-weekly $KEEP_WEEKLY"
            [[ $KEEP_MONTHLY -gt 0 ]] && retention_opts+=" --keep-monthly $KEEP_MONTHLY"
            
            if [[ -z "$retention_opts" ]]; then
                die "Cleanup requires at least one retention option (--keep-*)"
            fi
            
            cmd+="$retention_opts"
            extra_meta="keep-last=${KEEP_LAST}:keep-daily=${KEEP_DAILY}:keep-weekly=${KEEP_WEEKLY}:keep-monthly=${KEEP_MONTHLY}"
            ;;
        scrub)
            cmd="zpool scrub $POOL"
            ;;
    esac
    
    # Get next ID
    local id
    id=$(cron_get_next_id)
    
    # Add cron entry
    info "Adding cron task #$id: $TASK_TYPE for $POOL"
    info "Schedule: $schedule"
    info "Command: $cmd"
    
    cron_add_entry "$id" "$TASK_TYPE" "$POOL" "$schedule" "$cmd" "$extra_meta"
    
    success "Task #$id added successfully"
    
    if [[ "$JSON_OUTPUT" == "true" ]]; then
        echo "{\"id\": $id, \"type\": \"$TASK_TYPE\", \"pool\": \"$POOL\", \"schedule\": \"$schedule\"}"
    else
        echo ""
        echo "To view tasks: $0 list"
        echo "To remove:     $0 remove --id $id"
        echo "To test:       $0 test --id $id --dry-run"
    fi
}

cmd_list() {
    local type_filter=""
    
    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --type)
                type_filter="$2"
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
                shift
                ;;
        esac
    done
    
    # Get all entries from crontab
    local entries
    entries=$(crontab -l 2>/dev/null || true)
    
    if [[ -z "$entries" ]]; then
        if [[ "$JSON_OUTPUT" == "true" ]]; then
            echo '{"tasks": []}'
        else
            info "No cron entries found"
        fi
        return 0
    fi
    
    # Parse ZFSh entries
    local -a tasks=()
    local current_meta=""
    local in_task=false
    
    while IFS= read -r line; do
        if [[ "$line" =~ ^#\ ${CRON_TAG}: ]]; then
            current_meta="${line#\# ${CRON_TAG}:}"
            in_task=true
        elif [[ "$in_task" == "true" && -n "$line" && ! "$line" =~ ^# ]]; then
            # This is the command line
            local schedule="${line%% /*}"
            # Handle case where path doesn't start with /
            if [[ "$schedule" == "$line" ]]; then
                schedule="${line%% [a-z]*}"
            fi
            schedule=$(echo "$schedule" | awk '{print $1,$2,$3,$4,$5}')
            local cmd="${line#* }"
            cmd="${cmd#* }"
            cmd="${cmd#* }"
            cmd="${cmd#* }"
            cmd="${line#$schedule }"
            
            # Parse metadata
            parse_cron_meta "$current_meta"
            
            # Apply filter
            if [[ -n "$type_filter" && "$CRON_TYPE" != "$type_filter" ]]; then
                in_task=false
                continue
            fi
            
            tasks+=("${CRON_ID}|${CRON_TYPE}|${CRON_POOL}|${schedule}|${cmd}")
            in_task=false
        fi
    done <<< "$entries"
    
    if [[ ${#tasks[@]} -eq 0 ]]; then
        if [[ "$JSON_OUTPUT" == "true" ]]; then
            echo '{"tasks": []}'
        else
            info "No ZFSh tasks found"
        fi
        return 0
    fi
    
    if [[ "$JSON_OUTPUT" == "true" ]]; then
        echo '{"tasks": ['
        local first=true
        for task in "${tasks[@]}"; do
            IFS='|' read -r tid ttype tpool tschedule tcmd <<< "$task"
            [[ "$first" == "true" ]] && first=false || echo ","
            echo -n "{\"id\": $tid, \"type\": \"$ttype\", \"pool\": \"$tpool\", \"schedule\": \"$tschedule\"}"
        done
        echo ']}'
    else
        header "Scheduled ZFS Tasks"
        echo ""
        printf "%-4s %-10s %-15s %-20s %s\n" "ID" "TYPE" "POOL" "SCHEDULE" "COMMAND"
        printf "%-4s %-10s %-15s %-20s %s\n" "--" "----" "----" "--------" "-------"
        for task in "${tasks[@]}"; do
            IFS='|' read -r tid ttype tpool tschedule tcmd <<< "$task"
            # Truncate command for display
            local cmd_short="${tcmd:0:50}"
            [[ ${#tcmd} -gt 50 ]] && cmd_short+="..."
            printf "%-4s %-10s %-15s %-20s %s\n" "$tid" "$ttype" "$tpool" "$tschedule" "$cmd_short"
        done
    fi
}

cmd_remove() {
    local remove_id=""
    local remove_type=""
    local remove_pool=""
    local remove_all=false
    
    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --id)
                remove_id="$2"
                shift 2
                ;;
            --type)
                remove_type="$2"
                shift 2
                ;;
            --pool)
                remove_pool="$2"
                shift 2
                ;;
            --all)
                remove_all=true
                shift
                ;;
            -h|--help)
                show_remove_help
                exit 0
                ;;
            -*)
                die "Unknown option: $1"
                ;;
            *)
                shift
                ;;
        esac
    done
    
    if [[ -z "$remove_id" && -z "$remove_type" && -z "$remove_pool" && "$remove_all" == "false" ]]; then
        die "Specify --id, --type, --pool, or --all"
    fi
    
    check_root
    
    local current_crontab
    current_crontab=$(crontab -l 2>/dev/null || true)
    
    if [[ -z "$current_crontab" ]]; then
        info "No cron entries found"
        return 0
    fi
    
    # Count matching entries
    local match_count=0
    local in_task=false
    local current_meta=""
    
    while IFS= read -r line; do
        if [[ "$line" =~ ^#\ ${CRON_TAG}: ]]; then
            current_meta="${line#\# ${CRON_TAG}:}"
            parse_cron_meta "$current_meta"
            
            local matches=false
            
            if [[ "$remove_all" == "true" ]]; then
                matches=true
            elif [[ -n "$remove_id" && "$CRON_ID" == "$remove_id" ]]; then
                matches=true
            elif [[ -n "$remove_type" && "$CRON_TYPE" == "$remove_type" ]]; then
                if [[ -z "$remove_pool" || "$CRON_POOL" == "$remove_pool" ]]; then
                    matches=true
                fi
            elif [[ -n "$remove_pool" && "$CRON_POOL" == "$remove_pool" ]]; then
                matches=true
            fi
            
            [[ "$matches" == "true" ]] && ((match_count++))
        fi
    done <<< "$current_crontab"
    
    if [[ $match_count -eq 0 ]]; then
        info "No matching tasks found"
        return 0
    fi
    
    # Confirm removal
    if [[ "$remove_all" == "true" ]]; then
        echo "This will remove ALL ZFSh cron tasks ($match_count tasks)"
        if ! confirm "Are you sure?"; then
            echo "Aborted."
            return 0
        fi
    else
        info "Will remove $match_count task(s)"
    fi
    
    # Build new crontab
    local new_crontab=""
    local skip_next=false
    
    while IFS= read -r line; do
        if [[ "$skip_next" == "true" ]]; then
            skip_next=false
            continue
        fi
        
        if [[ "$line" =~ ^#\ ${CRON_TAG}: ]]; then
            current_meta="${line#\# ${CRON_TAG}:}"
            parse_cron_meta "$current_meta"
            
            local should_remove=false
            
            if [[ "$remove_all" == "true" ]]; then
                should_remove=true
            elif [[ -n "$remove_id" && "$CRON_ID" == "$remove_id" ]]; then
                should_remove=true
            elif [[ -n "$remove_type" && "$CRON_TYPE" == "$remove_type" ]]; then
                if [[ -z "$remove_pool" || "$CRON_POOL" == "$remove_pool" ]]; then
                    should_remove=true
                fi
            elif [[ -n "$remove_pool" && "$CRON_POOL" == "$remove_pool" ]]; then
                should_remove=true
            fi
            
            if [[ "$should_remove" == "true" ]]; then
                skip_next=true
                success "Removed task #$CRON_ID ($CRON_TYPE for $CRON_POOL)"
                continue
            fi
        fi
        
        new_crontab+="$line"$'\n'
    done <<< "$current_crontab"
    
    # Apply new crontab
    if [[ -n "$new_crontab" ]]; then
        echo "$new_crontab" | crontab -
    else
        crontab -r 2>/dev/null || true
    fi
    
    success "Removed $match_count task(s)"
    
    if [[ "$JSON_OUTPUT" == "true" ]]; then
        echo "{\"removed\": $match_count}"
    fi
}

cmd_test() {
    local test_id=""
    local dry_run=false
    
    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --id)
                test_id="$2"
                shift 2
                ;;
            --dry-run)
                dry_run=true
                shift
                ;;
            -h|--help)
                show_test_help
                exit 0
                ;;
            -*)
                die "Unknown option: $1"
                ;;
            *)
                shift
                ;;
        esac
    done
    
    [[ -z "$test_id" ]] && die "Task ID required (--id)"
    
    # Find task
    local entries
    entries=$(crontab -l 2>/dev/null || true)
    
    local found_cmd=""
    local found_type=""
    local found_pool=""
    local in_task=false
    local current_meta=""
    
    while IFS= read -r line; do
        if [[ "$line" =~ ^#\ ${CRON_TAG}: ]]; then
            current_meta="${line#\# ${CRON_TAG}:}"
            parse_cron_meta "$current_meta"
            
            if [[ "$CRON_ID" == "$test_id" ]]; then
                found_type="$CRON_TYPE"
                found_pool="$CRON_POOL"
                in_task=true
            fi
        elif [[ "$in_task" == "true" && -n "$line" && ! "$line" =~ ^# ]]; then
            # Extract command (skip schedule)
            found_cmd="${line#* }"
            found_cmd="${found_cmd#* }"
            found_cmd="${found_cmd#* }"
            found_cmd="${found_cmd#* }"
            found_cmd="${found_cmd#* }"
            break
        fi
    done <<< "$entries"
    
    if [[ -z "$found_cmd" ]]; then
        die "Task #$test_id not found"
    fi
    
    header "Test Task #$test_id"
    echo "Type: $found_type"
    echo "Pool: $found_pool"
    echo "Command: $found_cmd"
    echo ""
    
    if [[ "$dry_run" == "true" ]]; then
        info "Dry run - command would be:"
        echo "  $found_cmd"
        
        # For snapshot/backup commands, add --dry-run if supported
        if [[ "$found_cmd" == *"zfs-snapshot.sh cleanup"* ]]; then
            echo ""
            echo "Running with --dry-run:"
            eval "${found_cmd/ -y / --dry-run -y }" || true
        fi
    else
        info "Executing command..."
        echo ""
        
        if eval "$found_cmd"; then
            success "Task completed successfully"
        else
            error "Task failed"
            return 1
        fi
    fi
    
    if [[ "$JSON_OUTPUT" == "true" ]]; then
        echo "{\"id\": $test_id, \"type\": \"$found_type\", \"executed\": $([ "$dry_run" == "true" ] && echo "false" || echo "true")}"
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
        add)    cmd_add "$@" ;;
        list)   cmd_list "$@" ;;
        remove) cmd_remove "$@" ;;
        test)   cmd_test "$@" ;;
        -h|--help|help) show_help ;;
        *)      die "Unknown command: $command. Use -h for help." ;;
    esac
}

main "$@"
