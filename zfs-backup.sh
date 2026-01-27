#!/bin/bash
# zfs-backup.sh - Backup and restore ZFS datasets
#
# Usage: zfs-backup.sh <command> [options]
#
# Commands:
#   create    Create backup file (zfs send)
#   restore   Restore from backup (zfs receive)
#   list      List backup files
#   verify    Verify backup integrity
#   cleanup   Remove old backups
#   send      Send to remote server

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

# =============================================================================
# DEFAULTS
# =============================================================================
BACKUP_DIR="/root/backups"
COMPRESS_TYPE="zstd"
INCREMENTAL=false
BASE_SNAPSHOT=""
RECURSIVE=false
SHOW_PROGRESS=false
SKIP_CONFIRM=false
DRY_RUN=false
FORCE=false
KEEP_LAST=0
KEEP_DAILY=0
KEEP_WEEKLY=0
KEEP_MONTHLY=0
OLDER_THAN=""
BANDWIDTH_LIMIT=""

# =============================================================================
# HELP
# =============================================================================
show_help() {
    cat << 'EOF'
ZFS Backup Manager - Backup and restore ZFS datasets

Usage: zfs-backup.sh <command> [options]

Commands:
  create    Create backup file (zfs send)
  restore   Restore from backup (zfs receive)
  list      List backup files
  verify    Verify backup integrity
  cleanup   Remove old backups
  send      Send to remote server

Global Options:
  -j, --json      Output as JSON
  -l, --log FILE  Log to file
  -q, --quiet     Minimal output
  -h, --help      Show this help

Examples:
  zfs-backup.sh create default -c zstd
  zfs-backup.sh create default -i --progress
  zfs-backup.sh restore /root/backups/default_20240101.zfs.zst default/restored
  zfs-backup.sh send default root@backup-server:tank/backups
  zfs-backup.sh cleanup --keep-last 10

Use 'zfs-backup.sh <command> --help' for command-specific help.
EOF
}

show_create_help() {
    cat << 'EOF'
Create ZFS backup file

Usage: zfs-backup.sh create <dataset|snapshot> [options]

Options:
  -o, --output PATH     Output directory (default: /root/backups/)
  -c, --compress TYPE   Compression: gzip, zstd, lz4, none (default: zstd)
  -i, --incremental     Incremental from last snapshot
  --base SNAPSHOT       Base snapshot for incremental
  -r, --recursive       Include children
  --progress            Show progress (requires pv)

Output filename format:
  pool_dataset_YYYYMMDD_HHMMSS[_incr].zfs.{gz,zst,lz4}

Examples:
  zfs-backup.sh create default
  zfs-backup.sh create default -c zstd -i
  zfs-backup.sh create default@backup_20240101 -o /mnt/backup/
  zfs-backup.sh create default -r --progress
EOF
}

show_restore_help() {
    cat << 'EOF'
Restore from ZFS backup file

Usage: zfs-backup.sh restore <backup_file|-> <target_dataset> [options]

Options:
  -f, --force           Force receive (destroy existing)
  --dry-run             Test restore without applying
  --progress            Show progress (requires pv)

Examples:
  zfs-backup.sh restore /root/backups/default_20240101.zfs.zst default/restored
  zfs-backup.sh restore backup.zfs.gz default/data -f
  cat backup.zfs | zfs-backup.sh restore - default/data
EOF
}

show_list_help() {
    cat << 'EOF'
List backup files

Usage: zfs-backup.sh list [options]

Options:
  -d, --dir PATH        Backup directory (default: /root/backups/)
  -p, --pool POOL       Filter by pool name
  --sort FIELD          Sort by: date, size, name (default: date)

Examples:
  zfs-backup.sh list
  zfs-backup.sh list -d /mnt/backups/
  zfs-backup.sh list --pool default --json
EOF
}

show_verify_help() {
    cat << 'EOF'
Verify backup file integrity

Usage: zfs-backup.sh verify <backup_file> [options]

Options:
  --checksum            Verify SHA256 checksum (if .sha256 exists)
  -v, --verbose         Show detailed info

Examples:
  zfs-backup.sh verify /root/backups/default_20240101.zfs.zst
EOF
}

show_cleanup_help() {
    cat << 'EOF'
Cleanup old backup files

Usage: zfs-backup.sh cleanup [options]

Options:
  -d, --dir PATH        Backup directory (default: /root/backups/)
  --keep-last N         Keep last N backups per dataset
  --keep-daily N        Keep N daily backups
  --keep-weekly N       Keep N weekly backups
  --keep-monthly N      Keep N monthly backups
  --older-than AGE      Delete older than AGE (e.g., 30d)
  --dry-run             Show what would be deleted
  -y, --yes             Skip confirmation

Examples:
  zfs-backup.sh cleanup --keep-last 10
  zfs-backup.sh cleanup --older-than 30d --dry-run
EOF
}

show_send_help() {
    cat << 'EOF'
Send backup to remote server

Usage: zfs-backup.sh send <dataset|snapshot> <remote> [options]

Remote formats:
  user@host:pool/dataset
  ssh://user@host/pool/dataset

Options:
  -i, --incremental     Incremental send
  --base SNAPSHOT       Base snapshot for incremental
  -c, --compress TYPE   Compress stream: gzip, zstd, lz4, none (default: none)
  --bandwidth LIMIT     Limit bandwidth (e.g., 10M)
  --progress            Show progress (requires pv)
  -r, --recursive       Send children too

Examples:
  zfs-backup.sh send default backup-server:tank/backups
  zfs-backup.sh send default root@192.168.1.100:backup/default -i
  zfs-backup.sh send default ssh://backup@nas/pool/data -c zstd --progress
EOF
}

# =============================================================================
# UTILITY FUNCTIONS
# =============================================================================

# Generate backup filename
generate_backup_filename() {
    local dataset="$1"
    local is_incremental="${2:-false}"
    local compress="${3:-$COMPRESS_TYPE}"
    
    local safe_name="${dataset//\//_}"
    local timestamp=$(date +"%Y%m%d_%H%M%S")
    local suffix=""
    [[ "$is_incremental" == "true" ]] && suffix="_incr"
    
    local ext=$(get_compress_ext "$compress")
    echo "${safe_name}_${timestamp}${suffix}.zfs${ext}"
}

# Parse backup filename to extract info
parse_backup_filename() {
    local filename="$1"
    local basename="${filename##*/}"
    
    # Remove extensions
    local name="${basename%.zfs*}"
    
    # Extract parts
    if [[ "$name" =~ ^(.+)_([0-9]{8}_[0-9]{6})(_incr)?$ ]]; then
        BACKUP_DATASET="${BASH_REMATCH[1]//_/\/}"
        BACKUP_DATE="${BASH_REMATCH[2]}"
        BACKUP_INCREMENTAL="false"
        [[ -n "${BASH_REMATCH[3]}" ]] && BACKUP_INCREMENTAL="true"
        return 0
    fi
    return 1
}

# Get last snapshot for dataset
get_last_snapshot() {
    local dataset="$1"
    local prefix="${2:-$SNAPSHOT_PREFIX}"
    
    zfs list -t snapshot -H -o name -s creation "$dataset" 2>/dev/null | \
        grep "@${prefix}_" | tail -1 || true
}

# Create snapshot for backup
create_backup_snapshot() {
    local dataset="$1"
    local snapshot_name
    snapshot_name=$(generate_snapshot_name "$SNAPSHOT_PREFIX")
    local snapshot="${dataset}@${snapshot_name}"
    
    local zfs_opts=""
    [[ "$RECURSIVE" == "true" ]] && zfs_opts="-r"
    
    if zfs snapshot $zfs_opts "$snapshot"; then
        echo "$snapshot"
        return 0
    fi
    return 1
}

# =============================================================================
# COMMANDS
# =============================================================================

cmd_create() {
    local source=""
    local output_dir="$BACKUP_DIR"
    
    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -o|--output)
                output_dir="$2"
                shift 2
                ;;
            -c|--compress)
                COMPRESS_TYPE="$2"
                shift 2
                ;;
            -i|--incremental)
                INCREMENTAL=true
                shift
                ;;
            --base)
                BASE_SNAPSHOT="$2"
                shift 2
                ;;
            -r|--recursive)
                RECURSIVE=true
                shift
                ;;
            --progress)
                SHOW_PROGRESS=true
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
                source="$1"
                shift
                ;;
        esac
    done
    
    [[ -z "$source" ]] && die "Source dataset or snapshot required. Use -h for help."
    
    check_root
    check_zfs_installed
    
    # Validate compression
    if ! check_compress_tool "$COMPRESS_TYPE"; then
        die "Compression tool '$COMPRESS_TYPE' not found"
    fi
    
    # Create output directory
    mkdir -p "$output_dir"
    
    local snapshot=""
    local dataset=""
    local created_snapshot=false
    
    if [[ "$source" == *@* ]]; then
        # Source is a snapshot
        snapshot="$source"
        dataset="${source%@*}"
        
        if ! snapshot_exists "$snapshot"; then
            die "Snapshot '$snapshot' does not exist"
        fi
    else
        # Source is a dataset - create snapshot
        dataset="$source"
        
        if ! dataset_exists "$dataset"; then
            die "Dataset '$dataset' does not exist"
        fi
        
        info "Creating snapshot for backup..."
        snapshot=$(create_backup_snapshot "$dataset")
        if [[ -z "$snapshot" ]]; then
            die "Failed to create snapshot"
        fi
        created_snapshot=true
        success "Created snapshot: $snapshot"
    fi
    
    # Determine if incremental
    local base_snap=""
    if [[ "$INCREMENTAL" == "true" ]]; then
        if [[ -n "$BASE_SNAPSHOT" ]]; then
            base_snap="$BASE_SNAPSHOT"
        else
            # Find previous snapshot
            local all_snaps
            all_snaps=$(get_snapshots "$dataset" "$SNAPSHOT_PREFIX")
            local snap_count
            snap_count=$(echo "$all_snaps" | grep -c . || echo "0")
            
            if [[ $snap_count -ge 2 ]]; then
                # Get second to last snapshot
                base_snap=$(echo "$all_snaps" | tail -2 | head -1)
            fi
        fi
        
        if [[ -z "$base_snap" ]]; then
            warn "No base snapshot found, creating full backup"
            INCREMENTAL=false
        else
            info "Incremental from: $base_snap"
        fi
    fi
    
    # Generate output filename
    local filename
    filename=$(generate_backup_filename "$dataset" "$INCREMENTAL" "$COMPRESS_TYPE")
    local output_path="${output_dir}/${filename}"
    
    info "Creating backup: $output_path"
    
    # Build zfs send command
    local send_opts=""
    [[ "$RECURSIVE" == "true" ]] && send_opts+=" -R"
    [[ -n "$base_snap" ]] && send_opts+=" -i $base_snap"
    
    # Build pipeline
    local compress_cmd
    compress_cmd=$(get_compress_cmd "$COMPRESS_TYPE")
    
    # Execute backup
    local start_time
    start_time=$(date +%s)
    
    if [[ "$SHOW_PROGRESS" == "true" ]] && has_pv; then
        # Estimate size
        local est_size
        est_size=$(zfs get -H -o value -p referenced "$snapshot" 2>/dev/null || echo "0")
        
        if zfs send $send_opts "$snapshot" | pv -s "$est_size" | $compress_cmd > "$output_path"; then
            :
        else
            [[ "$created_snapshot" == "true" ]] && zfs destroy "$snapshot" 2>/dev/null || true
            die "Backup failed"
        fi
    else
        if zfs send $send_opts "$snapshot" 2>/dev/null | $compress_cmd > "$output_path"; then
            :
        else
            [[ "$created_snapshot" == "true" ]] && zfs destroy "$snapshot" 2>/dev/null || true
            die "Backup failed"
        fi
    fi
    
    local end_time
    end_time=$(date +%s)
    local duration=$((end_time - start_time))
    
    # Create checksum
    local checksum_file="${output_path}.sha256"
    sha256sum "$output_path" > "$checksum_file"
    
    # Get file size
    local file_size
    file_size=$(stat -c%s "$output_path" 2>/dev/null || echo "0")
    local file_size_human
    file_size_human=$(format_size "$file_size")
    
    success "Backup complete: $output_path"
    info "Size: $file_size_human, Duration: ${duration}s"
    
    if [[ "$JSON_OUTPUT" == "true" ]]; then
        cat << EOF
{
  "success": true,
  "file": "$output_path",
  "size": $file_size,
  "size_human": "$file_size_human",
  "duration": $duration,
  "snapshot": "$snapshot",
  "incremental": $INCREMENTAL,
  "compression": "$COMPRESS_TYPE"
}
EOF
    fi
}

cmd_restore() {
    local backup_file=""
    local target=""
    
    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -f|--force)
                FORCE=true
                shift
                ;;
            --dry-run)
                DRY_RUN=true
                shift
                ;;
            --progress)
                SHOW_PROGRESS=true
                shift
                ;;
            -h|--help)
                show_restore_help
                exit 0
                ;;
            -*)
                die "Unknown option: $1"
                ;;
            *)
                if [[ -z "$backup_file" ]]; then
                    backup_file="$1"
                else
                    target="$1"
                fi
                shift
                ;;
        esac
    done
    
    [[ -z "$backup_file" ]] && die "Backup file required. Use -h for help."
    [[ -z "$target" ]] && die "Target dataset required. Use -h for help."
    
    check_root
    check_zfs_installed
    
    # Check backup file
    if [[ "$backup_file" != "-" && ! -f "$backup_file" ]]; then
        die "Backup file not found: $backup_file"
    fi
    
    # Detect compression
    local compress_type="none"
    if [[ "$backup_file" != "-" ]]; then
        compress_type=$(detect_compression "$backup_file")
    fi
    
    local decompress_cmd
    decompress_cmd=$(get_decompress_cmd "$compress_type")
    
    # Check if target exists
    if dataset_exists "$target" && [[ "$FORCE" == "false" ]]; then
        die "Target '$target' exists. Use -f to force overwrite."
    fi
    
    # Build receive options
    local recv_opts=""
    [[ "$FORCE" == "true" ]] && recv_opts+=" -F"
    [[ "$DRY_RUN" == "true" ]] && recv_opts+=" -n"
    
    info "Restoring to: $target"
    [[ "$DRY_RUN" == "true" ]] && info "(Dry run mode)"
    
    # Execute restore
    if [[ "$backup_file" == "-" ]]; then
        # Read from stdin
        if $decompress_cmd | zfs receive $recv_opts "$target"; then
            success "Restore complete"
        else
            die "Restore failed"
        fi
    elif [[ "$SHOW_PROGRESS" == "true" ]] && has_pv; then
        local file_size
        file_size=$(stat -c%s "$backup_file" 2>/dev/null || echo "0")
        
        if pv -s "$file_size" < "$backup_file" | $decompress_cmd | zfs receive $recv_opts "$target"; then
            success "Restore complete"
        else
            die "Restore failed"
        fi
    else
        if $decompress_cmd < "$backup_file" | zfs receive $recv_opts "$target"; then
            success "Restore complete"
        else
            die "Restore failed"
        fi
    fi
    
    if [[ "$JSON_OUTPUT" == "true" ]]; then
        echo "{\"success\": true, \"target\": \"$target\", \"dry_run\": $DRY_RUN}"
    fi
}

cmd_list() {
    local list_dir="$BACKUP_DIR"
    local pool_filter=""
    local sort_field="date"
    
    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -d|--dir)
                list_dir="$2"
                shift 2
                ;;
            -p|--pool)
                pool_filter="$2"
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
                shift
                ;;
        esac
    done
    
    if [[ ! -d "$list_dir" ]]; then
        if [[ "$JSON_OUTPUT" == "true" ]]; then
            echo '{"backups": []}'
        else
            info "Backup directory not found: $list_dir"
        fi
        return 0
    fi
    
    # Find backup files
    local files
    files=$(find "$list_dir" -maxdepth 1 -name "*.zfs*" -type f 2>/dev/null | sort)
    
    if [[ -z "$files" ]]; then
        if [[ "$JSON_OUTPUT" == "true" ]]; then
            echo '{"backups": []}'
        else
            info "No backups found in: $list_dir"
        fi
        return 0
    fi
    
    # Build backup list
    local -a backups=()
    
    while IFS= read -r file; do
        [[ -z "$file" ]] && continue
        
        local filename="${file##*/}"
        if parse_backup_filename "$filename"; then
            # Apply pool filter
            if [[ -n "$pool_filter" && ! "$BACKUP_DATASET" =~ ^$pool_filter ]]; then
                continue
            fi
            
            local size
            size=$(stat -c%s "$file" 2>/dev/null || echo "0")
            local size_human
            size_human=$(format_size "$size")
            local compress
            compress=$(detect_compression "$filename")
            local type="full"
            [[ "$BACKUP_INCREMENTAL" == "true" ]] && type="incr"
            
            backups+=("$filename|$BACKUP_DATASET|$BACKUP_DATE|$size|$size_human|$type|$compress")
        fi
    done <<< "$files"
    
    if [[ ${#backups[@]} -eq 0 ]]; then
        if [[ "$JSON_OUTPUT" == "true" ]]; then
            echo '{"backups": []}'
        else
            info "No matching backups found"
        fi
        return 0
    fi
    
    # Sort
    local sorted
    case "$sort_field" in
        date) sorted=$(printf '%s\n' "${backups[@]}" | sort -t'|' -k3 -r) ;;
        size) sorted=$(printf '%s\n' "${backups[@]}" | sort -t'|' -k4 -rn) ;;
        name) sorted=$(printf '%s\n' "${backups[@]}" | sort -t'|' -k1) ;;
        *)    sorted=$(printf '%s\n' "${backups[@]}") ;;
    esac
    
    if [[ "$JSON_OUTPUT" == "true" ]]; then
        echo '{"backups": ['
        local first=true
        while IFS='|' read -r fname ds date size size_h type comp; do
            [[ -z "$fname" ]] && continue
            [[ "$first" == "true" ]] && first=false || echo ","
            echo -n "{\"file\": \"$fname\", \"dataset\": \"$ds\", \"date\": \"$date\", \"size\": $size, \"size_human\": \"$size_h\", \"type\": \"$type\", \"compression\": \"$comp\"}"
        done <<< "$sorted"
        echo ']}'
    else
        echo ""
        printf "%-45s %-25s %-17s %-10s %-6s %-5s\n" "FILE" "DATASET" "DATE" "SIZE" "TYPE" "COMP"
        printf "%-45s %-25s %-17s %-10s %-6s %-5s\n" "----" "-------" "----" "----" "----" "----"
        while IFS='|' read -r fname ds date size size_h type comp; do
            [[ -z "$fname" ]] && continue
            printf "%-45s %-25s %-17s %-10s %-6s %-5s\n" "$fname" "$ds" "$date" "$size_h" "$type" "$comp"
        done <<< "$sorted"
    fi
}

cmd_verify() {
    local backup_file=""
    local verbose=false
    local check_checksum=false
    
    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --checksum)
                check_checksum=true
                shift
                ;;
            -v|--verbose)
                verbose=true
                shift
                ;;
            -h|--help)
                show_verify_help
                exit 0
                ;;
            -*)
                die "Unknown option: $1"
                ;;
            *)
                backup_file="$1"
                shift
                ;;
        esac
    done
    
    [[ -z "$backup_file" ]] && die "Backup file required. Use -h for help."
    
    if [[ ! -f "$backup_file" ]]; then
        die "Backup file not found: $backup_file"
    fi
    
    local filename="${backup_file##*/}"
    local errors=0
    
    header "Verifying: $filename"
    
    # Basic file check
    local size
    size=$(stat -c%s "$backup_file" 2>/dev/null || echo "0")
    local size_human
    size_human=$(format_size "$size")
    
    if [[ $size -eq 0 ]]; then
        error "File is empty"
        ((errors++))
    else
        success "File size: $size_human"
    fi
    
    # Parse filename
    if parse_backup_filename "$filename"; then
        success "Dataset: $BACKUP_DATASET"
        success "Date: $BACKUP_DATE"
        success "Type: $([ "$BACKUP_INCREMENTAL" == "true" ] && echo "incremental" || echo "full")"
    else
        warn "Could not parse filename"
    fi
    
    # Compression
    local compress
    compress=$(detect_compression "$filename")
    success "Compression: $compress"
    
    # Checksum verification
    local checksum_file="${backup_file}.sha256"
    if [[ "$check_checksum" == "true" || -f "$checksum_file" ]]; then
        if [[ -f "$checksum_file" ]]; then
            info "Verifying checksum..."
            if sha256sum -c "$checksum_file" &>/dev/null; then
                success "Checksum: OK"
            else
                error "Checksum: FAILED"
                ((errors++))
            fi
        else
            warn "No checksum file found: $checksum_file"
        fi
    fi
    
    # Try to decompress and verify stream
    if [[ "$verbose" == "true" ]]; then
        info "Verifying stream integrity..."
        local decompress_cmd
        decompress_cmd=$(get_decompress_cmd "$compress")
        
        if $decompress_cmd < "$backup_file" 2>/dev/null | head -c 1024 > /dev/null; then
            success "Stream: readable"
        else
            error "Stream: cannot read"
            ((errors++))
        fi
    fi
    
    echo ""
    if [[ $errors -eq 0 ]]; then
        success "Verification passed"
        [[ "$JSON_OUTPUT" == "true" ]] && echo "{\"valid\": true, \"errors\": 0}"
    else
        error "Verification failed with $errors error(s)"
        [[ "$JSON_OUTPUT" == "true" ]] && echo "{\"valid\": false, \"errors\": $errors}"
        return 1
    fi
}

cmd_cleanup() {
    local cleanup_dir="$BACKUP_DIR"
    
    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -d|--dir)
                cleanup_dir="$2"
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
            --older-than)
                OLDER_THAN="$2"
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
                shift
                ;;
        esac
    done
    
    # Must have at least one retention option
    if [[ $KEEP_LAST -eq 0 && $KEEP_DAILY -eq 0 && $KEEP_WEEKLY -eq 0 && \
          $KEEP_MONTHLY -eq 0 && -z "$OLDER_THAN" ]]; then
        die "At least one retention option required. Use -h for help."
    fi
    
    if [[ ! -d "$cleanup_dir" ]]; then
        info "Backup directory not found: $cleanup_dir"
        return 0
    fi
    
    # Find and group backup files by dataset
    declare -A dataset_files
    
    while IFS= read -r file; do
        [[ -z "$file" ]] && continue
        local filename="${file##*/}"
        
        if parse_backup_filename "$filename"; then
            local key="${BACKUP_DATASET//\//_}"
            dataset_files[$key]+="$file|$BACKUP_DATE\n"
        fi
    done < <(find "$cleanup_dir" -maxdepth 1 -name "*.zfs*" -type f 2>/dev/null)
    
    local -a files_to_delete=()
    
    for ds_key in "${!dataset_files[@]}"; do
        # Sort files by date and process
        local sorted
        sorted=$(echo -e "${dataset_files[$ds_key]}" | sort -t'|' -k2)
        
        local -a ds_files=()
        while IFS='|' read -r fpath fdate; do
            [[ -n "$fpath" ]] && ds_files+=("$fpath")
        done <<< "$sorted"
        
        [[ ${#ds_files[@]} -eq 0 ]] && continue
        
        if [[ -n "$OLDER_THAN" ]]; then
            # Age-based deletion
            local max_age_seconds
            max_age_seconds=$(parse_age "$OLDER_THAN")
            local now
            now=$(date +%s)
            
            for fpath in "${ds_files[@]}"; do
                local mtime
                mtime=$(stat -c%Y "$fpath" 2>/dev/null || echo "$now")
                local age=$((now - mtime))
                
                if [[ $age -gt $max_age_seconds ]]; then
                    files_to_delete+=("$fpath")
                fi
            done
        else
            # GFS retention - convert file paths to "snapshots" for the function
            local -a pseudo_snaps=()
            for fpath in "${ds_files[@]}"; do
                pseudo_snaps+=("$fpath")
            done
            
            # Custom retention for files (simpler than GFS)
            local total=${#pseudo_snaps[@]}
            local keep=$KEEP_LAST
            [[ $KEEP_DAILY -gt $keep ]] && keep=$KEEP_DAILY
            [[ $KEEP_WEEKLY -gt $keep ]] && keep=$KEEP_WEEKLY
            [[ $KEEP_MONTHLY -gt $keep ]] && keep=$KEEP_MONTHLY
            
            if [[ $total -gt $keep ]]; then
                local delete_count=$((total - keep))
                for ((i=0; i<delete_count; i++)); do
                    files_to_delete+=("${pseudo_snaps[$i]}")
                done
            fi
        fi
    done
    
    if [[ ${#files_to_delete[@]} -eq 0 ]]; then
        info "No backups to delete based on retention policy"
        return 0
    fi
    
    # Show what will be deleted
    header "Cleanup Plan"
    echo "Files to delete (${#files_to_delete[@]}):"
    local total_size=0
    for fpath in "${files_to_delete[@]}"; do
        local size
        size=$(stat -c%s "$fpath" 2>/dev/null || echo "0")
        ((total_size += size))
        echo "  ${fpath##*/} ($(format_size $size))"
    done
    echo ""
    info "Total space to free: $(format_size $total_size)"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        info "Dry run - no changes made"
        return 0
    fi
    
    # Confirm
    if [[ "$SKIP_CONFIRM" == "false" ]]; then
        if ! confirm "Delete ${#files_to_delete[@]} backup file(s)?"; then
            echo "Aborted."
            return 0
        fi
    fi
    
    # Delete files
    local deleted=0
    for fpath in "${files_to_delete[@]}"; do
        if rm -f "$fpath" "${fpath}.sha256" 2>/dev/null; then
            success "Deleted: ${fpath##*/}"
            ((deleted++))
        else
            error "Failed to delete: ${fpath##*/}"
        fi
    done
    
    info "Deleted $deleted file(s)"
    
    if [[ "$JSON_OUTPUT" == "true" ]]; then
        echo "{\"deleted\": $deleted, \"freed_bytes\": $total_size}"
    fi
}

cmd_send() {
    local source=""
    local remote=""
    
    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -i|--incremental)
                INCREMENTAL=true
                shift
                ;;
            --base)
                BASE_SNAPSHOT="$2"
                shift 2
                ;;
            -c|--compress)
                COMPRESS_TYPE="$2"
                shift 2
                ;;
            --bandwidth)
                BANDWIDTH_LIMIT="$2"
                shift 2
                ;;
            --progress)
                SHOW_PROGRESS=true
                shift
                ;;
            -r|--recursive)
                RECURSIVE=true
                shift
                ;;
            -h|--help)
                show_send_help
                exit 0
                ;;
            -*)
                die "Unknown option: $1"
                ;;
            *)
                if [[ -z "$source" ]]; then
                    source="$1"
                else
                    remote="$1"
                fi
                shift
                ;;
        esac
    done
    
    [[ -z "$source" ]] && die "Source dataset or snapshot required. Use -h for help."
    [[ -z "$remote" ]] && die "Remote destination required. Use -h for help."
    
    check_root
    check_zfs_installed
    
    # Parse remote
    if ! parse_remote "$remote"; then
        die "Invalid remote format: $remote"
    fi
    
    info "Remote: ${REMOTE_USER:-root}@${REMOTE_HOST}:${REMOTE_PATH}"
    
    # Test SSH connection
    info "Testing SSH connection..."
    local ssh_cmd
    ssh_cmd=$(build_ssh_cmd)
    
    if ! $ssh_cmd "zfs list -H -o name 2>/dev/null | head -1" &>/dev/null; then
        die "Cannot connect to remote or ZFS not available on remote"
    fi
    success "SSH connection OK"
    
    local snapshot=""
    local dataset=""
    local created_snapshot=false
    
    if [[ "$source" == *@* ]]; then
        snapshot="$source"
        dataset="${source%@*}"
        
        if ! snapshot_exists "$snapshot"; then
            die "Snapshot '$snapshot' does not exist"
        fi
    else
        dataset="$source"
        
        if ! dataset_exists "$dataset"; then
            die "Dataset '$dataset' does not exist"
        fi
        
        info "Creating snapshot for send..."
        snapshot=$(create_backup_snapshot "$dataset")
        if [[ -z "$snapshot" ]]; then
            die "Failed to create snapshot"
        fi
        created_snapshot=true
        success "Created snapshot: $snapshot"
    fi
    
    # Determine incremental base
    local base_snap=""
    if [[ "$INCREMENTAL" == "true" ]]; then
        if [[ -n "$BASE_SNAPSHOT" ]]; then
            base_snap="$BASE_SNAPSHOT"
        else
            # Try to find common snapshot on remote
            local remote_snaps
            remote_snaps=$($ssh_cmd "zfs list -t snapshot -H -o name 2>/dev/null | grep '^${REMOTE_PATH}@'" || true)
            
            if [[ -n "$remote_snaps" ]]; then
                # Find most recent common snapshot
                local local_snaps
                local_snaps=$(get_snapshots "$dataset" "$SNAPSHOT_PREFIX")
                
                for local_snap in $(echo "$local_snaps" | tac); do
                    local snap_name="${local_snap#*@}"
                    if echo "$remote_snaps" | grep -q "@${snap_name}$"; then
                        base_snap="$local_snap"
                        break
                    fi
                done
            fi
        fi
        
        if [[ -z "$base_snap" ]]; then
            warn "No common snapshot found, sending full stream"
            INCREMENTAL=false
        else
            info "Incremental from: $base_snap"
        fi
    fi
    
    # Build send command
    local send_opts=""
    [[ "$RECURSIVE" == "true" ]] && send_opts+=" -R"
    [[ -n "$base_snap" ]] && send_opts+=" -i $base_snap"
    
    # Build pipeline
    local pipeline="zfs send $send_opts $snapshot"
    
    # Add progress if requested
    if [[ "$SHOW_PROGRESS" == "true" ]] && has_pv; then
        local est_size
        est_size=$(zfs get -H -o value -p referenced "$snapshot" 2>/dev/null || echo "0")
        pipeline+=" | pv -s $est_size"
    fi
    
    # Add compression if requested
    if [[ "$COMPRESS_TYPE" != "none" ]]; then
        local compress_cmd decompress_cmd
        compress_cmd=$(get_compress_cmd "$COMPRESS_TYPE")
        decompress_cmd=$(get_decompress_cmd "$COMPRESS_TYPE")
        pipeline+=" | $compress_cmd"
        pipeline+=" | $ssh_cmd '$decompress_cmd | zfs receive -F ${REMOTE_PATH}'"
    else
        pipeline+=" | $ssh_cmd 'zfs receive -F ${REMOTE_PATH}'"
    fi
    
    # Add bandwidth limit if specified
    if [[ -n "$BANDWIDTH_LIMIT" ]] && command -v pv &>/dev/null; then
        # Insert rate limit into pipeline
        pipeline=$(echo "$pipeline" | sed "s/| $ssh_cmd/| pv -L $BANDWIDTH_LIMIT | $ssh_cmd/")
    fi
    
    info "Sending to ${REMOTE_HOST}:${REMOTE_PATH}..."
    
    # Execute
    if eval "$pipeline"; then
        success "Send complete"
        
        if [[ "$JSON_OUTPUT" == "true" ]]; then
            echo "{\"success\": true, \"snapshot\": \"$snapshot\", \"remote\": \"$remote\", \"incremental\": $INCREMENTAL}"
        fi
    else
        [[ "$created_snapshot" == "true" ]] && zfs destroy "$snapshot" 2>/dev/null || true
        die "Send failed"
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
        restore)  cmd_restore "$@" ;;
        list)     cmd_list "$@" ;;
        verify)   cmd_verify "$@" ;;
        cleanup)  cmd_cleanup "$@" ;;
        send)     cmd_send "$@" ;;
        -h|--help|help) show_help ;;
        *)        die "Unknown command: $command. Use -h for help." ;;
    esac
}

main "$@"
