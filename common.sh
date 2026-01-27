#!/bin/bash
# common.sh - Shared library for ZFS helper scripts
# Source this file: source "$(dirname "$0")/common.sh"

set -euo pipefail

# =============================================================================
# COLORS
# =============================================================================
if [[ -t 1 ]]; then
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    YELLOW='\033[1;33m'
    BLUE='\033[0;34m'
    CYAN='\033[0;36m'
    BOLD='\033[1m'
    NC='\033[0m'
else
    RED=''
    GREEN=''
    YELLOW=''
    BLUE=''
    CYAN=''
    BOLD=''
    NC=''
fi

# =============================================================================
# GLOBAL VARIABLES
# =============================================================================
JSON_OUTPUT=false
LOG_FILE=""
QUIET=false
SCRIPT_NAME="$(basename "$0")"

# =============================================================================
# OUTPUT FUNCTIONS
# =============================================================================
_log_to_file() {
    if [[ -n "$LOG_FILE" ]]; then
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] [$SCRIPT_NAME] $1" >> "$LOG_FILE"
    fi
}

info() {
    _log_to_file "INFO: $1"
    if [[ "$QUIET" == "false" && "$JSON_OUTPUT" == "false" ]]; then
        echo -e "${BLUE}[INFO]${NC} $1"
    fi
}

success() {
    _log_to_file "OK: $1"
    if [[ "$QUIET" == "false" && "$JSON_OUTPUT" == "false" ]]; then
        echo -e "${GREEN}[OK]${NC} $1"
    fi
}

warn() {
    _log_to_file "WARN: $1"
    if [[ "$JSON_OUTPUT" == "false" ]]; then
        echo -e "${YELLOW}[WARN]${NC} $1" >&2
    fi
}

error() {
    _log_to_file "ERROR: $1"
    if [[ "$JSON_OUTPUT" == "false" ]]; then
        echo -e "${RED}[ERROR]${NC} $1" >&2
    fi
}

die() {
    error "$1"
    exit 1
}

header() {
    if [[ "$QUIET" == "false" && "$JSON_OUTPUT" == "false" ]]; then
        echo -e "\n${BOLD}$1${NC}"
        echo -e "${BOLD}$(printf '=%.0s' $(seq 1 ${#1}))${NC}"
    fi
}

# =============================================================================
# JSON HELPERS
# =============================================================================
declare -a _JSON_PAIRS=()

json_init() {
    _JSON_PAIRS=()
}

json_add() {
    local key="$1"
    local value="$2"
    local type="${3:-string}"  # string, number, bool, raw
    
    case "$type" in
        string)
            _JSON_PAIRS+=("\"$key\": \"$value\"")
            ;;
        number|bool|raw)
            _JSON_PAIRS+=("\"$key\": $value")
            ;;
    esac
}

json_output() {
    local IFS=','
    echo "{${_JSON_PAIRS[*]}}"
}

# Build JSON object from key-value pairs
json_object() {
    local result="{"
    local first=true
    while [[ $# -gt 0 ]]; do
        local key="$1"
        local value="$2"
        local type="${3:-string}"
        shift 3 || break
        
        if [[ "$first" == "true" ]]; then
            first=false
        else
            result+=","
        fi
        
        case "$type" in
            string)
                result+="\"$key\":\"$value\""
                ;;
            *)
                result+="\"$key\":$value"
                ;;
        esac
    done
    result+="}"
    echo "$result"
}

# =============================================================================
# VALIDATION FUNCTIONS
# =============================================================================
check_root() {
    if [[ $EUID -ne 0 ]]; then
        die "This script must be run as root"
    fi
}

check_zfs_installed() {
    if ! command -v zpool &> /dev/null; then
        die "ZFS is not installed. Install with: apt install zfsutils-linux"
    fi
}

check_incus_installed() {
    if ! command -v incus &> /dev/null; then
        die "Incus is not installed"
    fi
}

pool_exists() {
    local pool="$1"
    zpool list "$pool" &> /dev/null
}

dataset_exists() {
    local dataset="$1"
    zfs list "$dataset" &> /dev/null
}

# =============================================================================
# UTILITY FUNCTIONS
# =============================================================================

# Get free space in bytes for a path
get_free_space() {
    local path="$1"
    local dir="$path"
    
    # Find existing parent directory
    while [[ ! -d "$dir" ]]; do
        dir="$(dirname "$dir")"
    done
    
    df --output=avail -B1 "$dir" | tail -1
}

# Parse size string to bytes (e.g., 50G -> 53687091200)
parse_size() {
    local size="$1"
    local number="${size//[^0-9.]/}"
    local suffix="${size//[0-9.]/}"
    suffix="${suffix^^}"  # uppercase
    
    case "$suffix" in
        K|KB) echo "$((${number%.*} * 1024))" ;;
        M|MB) echo "$((${number%.*} * 1024 * 1024))" ;;
        G|GB) echo "$((${number%.*} * 1024 * 1024 * 1024))" ;;
        T|TB) echo "$((${number%.*} * 1024 * 1024 * 1024 * 1024))" ;;
        *)    echo "${number%.*}" ;;
    esac
}

# Format bytes to human readable (e.g., 53687091200 -> 50.0G)
format_size() {
    local bytes="$1"
    
    if [[ $bytes -ge $((1024**4)) ]]; then
        echo "$(awk "BEGIN {printf \"%.1fT\", $bytes / (1024^4)}")"
    elif [[ $bytes -ge $((1024**3)) ]]; then
        echo "$(awk "BEGIN {printf \"%.1fG\", $bytes / (1024^3)}")"
    elif [[ $bytes -ge $((1024**2)) ]]; then
        echo "$(awk "BEGIN {printf \"%.1fM\", $bytes / (1024^2)}")"
    elif [[ $bytes -ge 1024 ]]; then
        echo "$(awk "BEGIN {printf \"%.1fK\", $bytes / 1024}")"
    else
        echo "${bytes}B"
    fi
}

# Get pool backend type (file or device)
get_pool_backend_type() {
    local pool="$1"
    local vdev
    vdev=$(zpool status "$pool" | grep -E '^\s+/' | awk '{print $1}' | head -1)
    
    if [[ -f "$vdev" ]]; then
        echo "file"
    elif [[ -b "$vdev" ]]; then
        echo "device"
    else
        echo "unknown"
    fi
}

# Get pool backend path (file or device path)
get_pool_backend_path() {
    local pool="$1"
    zpool status "$pool" | grep -E '^\s+/' | awk '{print $1}' | head -1
}

# Get list of all ZFS pools
get_pools() {
    zpool list -H -o name 2>/dev/null || true
}

# Get pool property
get_pool_prop() {
    local pool="$1"
    local prop="$2"
    zpool get -H -o value "$prop" "$pool" 2>/dev/null || echo ""
}

# Get dataset property
get_dataset_prop() {
    local dataset="$1"
    local prop="$2"
    zfs get -H -o value "$prop" "$dataset" 2>/dev/null || echo ""
}

# =============================================================================
# INTERACTIVE HELPERS
# =============================================================================

# Prompt for input with default value
# Usage: prompt "Question" "default_value"
# Result in $REPLY
prompt() {
    local question="$1"
    local default="${2:-}"
    
    if [[ -n "$default" ]]; then
        read -rp "$question [$default]: " REPLY
        REPLY="${REPLY:-$default}"
    else
        read -rp "$question: " REPLY
    fi
}

# Prompt for yes/no
# Usage: prompt_yn "Question" "y|n"
# Returns 0 for yes, 1 for no
prompt_yn() {
    local question="$1"
    local default="${2:-y}"
    local prompt_text
    
    if [[ "$default" == "y" ]]; then
        prompt_text="$question (Y/n): "
    else
        prompt_text="$question (y/N): "
    fi
    
    read -rp "$prompt_text" REPLY
    REPLY="${REPLY:-$default}"
    REPLY="${REPLY,,}"  # lowercase
    
    [[ "$REPLY" == "y" || "$REPLY" == "yes" ]]
}

# Prompt to select from list
# Usage: prompt_select "Question" "opt1" "opt2" "opt3"
# Result in $REPLY (selected value)
prompt_select() {
    local question="$1"
    shift
    local options=("$@")
    local i=1
    
    echo "$question"
    for opt in "${options[@]}"; do
        echo "  $i. $opt"
        ((i++))
    done
    
    while true; do
        read -rp "Select [1-${#options[@]}]: " REPLY
        if [[ "$REPLY" =~ ^[0-9]+$ ]] && [[ "$REPLY" -ge 1 ]] && [[ "$REPLY" -le ${#options[@]} ]]; then
            REPLY="${options[$((REPLY-1))]}"
            return 0
        fi
        echo "Invalid selection"
    done
}

# Confirm action
# Usage: confirm "Are you sure?"
# Returns 0 for yes, 1 for no
confirm() {
    local message="${1:-Proceed?}"
    prompt_yn "$message" "y"
}

# =============================================================================
# COMMON ARGUMENT PARSING
# =============================================================================
# Call this to parse common args: parse_common_args "$@"
# Returns remaining args in REMAINING_ARGS array
declare -a REMAINING_ARGS=()

parse_common_args() {
    REMAINING_ARGS=()
    
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -j|--json)
                JSON_OUTPUT=true
                shift
                ;;
            -l|--log)
                LOG_FILE="${2:-/var/log/zfsh.log}"
                shift 2 || shift
                ;;
            -q|--quiet)
                QUIET=true
                shift
                ;;
            *)
                REMAINING_ARGS+=("$1")
                shift
                ;;
        esac
    done
}

# =============================================================================
# SNAPSHOT HELPERS
# =============================================================================

# Default snapshot naming
SNAPSHOT_PREFIX="${SNAPSHOT_PREFIX:-backup}"
SNAPSHOT_DATE_FORMAT="${SNAPSHOT_DATE_FORMAT:-%Y%m%d_%H%M%S}"

# Generate snapshot name
# Usage: generate_snapshot_name [prefix]
generate_snapshot_name() {
    local prefix="${1:-$SNAPSHOT_PREFIX}"
    echo "${prefix}_$(date +"$SNAPSHOT_DATE_FORMAT")"
}

# Check if snapshot exists
snapshot_exists() {
    local snapshot="$1"
    zfs list -t snapshot "$snapshot" &>/dev/null
}

# Get snapshots for dataset
# Usage: get_snapshots <dataset> [prefix_filter]
get_snapshots() {
    local dataset="$1"
    local prefix="${2:-}"
    
    if [[ -n "$prefix" ]]; then
        zfs list -t snapshot -H -o name -s creation 2>/dev/null | grep "^${dataset}@${prefix}" || true
    else
        zfs list -t snapshot -H -o name -s creation 2>/dev/null | grep "^${dataset}@" || true
    fi
}

# Get snapshot creation time as epoch
get_snapshot_creation() {
    local snapshot="$1"
    zfs get -H -o value -p creation "$snapshot" 2>/dev/null || echo "0"
}

# =============================================================================
# AGE/TIME PARSING
# =============================================================================

# Parse age string to seconds
# Usage: parse_age "7d" -> 604800
parse_age() {
    local age="$1"
    local number="${age//[^0-9]/}"
    local unit="${age//[0-9]/}"
    unit="${unit,,}"  # lowercase
    
    case "$unit" in
        s|sec|second|seconds) echo "$number" ;;
        m|min|minute|minutes) echo "$((number * 60))" ;;
        h|hour|hours)         echo "$((number * 3600))" ;;
        d|day|days)           echo "$((number * 86400))" ;;
        w|week|weeks)         echo "$((number * 604800))" ;;
        mo|month|months)      echo "$((number * 2592000))" ;;  # 30 days
        y|year|years)         echo "$((number * 31536000))" ;; # 365 days
        *)                    echo "$number" ;;
    esac
}

# Format seconds to human readable age
format_age() {
    local seconds="$1"
    
    if [[ $seconds -ge 31536000 ]]; then
        echo "$((seconds / 31536000))y"
    elif [[ $seconds -ge 2592000 ]]; then
        echo "$((seconds / 2592000))mo"
    elif [[ $seconds -ge 604800 ]]; then
        echo "$((seconds / 604800))w"
    elif [[ $seconds -ge 86400 ]]; then
        echo "$((seconds / 86400))d"
    elif [[ $seconds -ge 3600 ]]; then
        echo "$((seconds / 3600))h"
    elif [[ $seconds -ge 60 ]]; then
        echo "$((seconds / 60))m"
    else
        echo "${seconds}s"
    fi
}

# Get age of snapshot in seconds
get_snapshot_age() {
    local snapshot="$1"
    local creation
    creation=$(get_snapshot_creation "$snapshot")
    local now
    now=$(date +%s)
    echo "$((now - creation))"
}

# =============================================================================
# RETENTION POLICY (GFS - Grandfather-Father-Son)
# =============================================================================

# Get period key for a timestamp
# Usage: get_period_key <epoch> <period_type>
# period_type: daily, weekly, monthly
get_period_key() {
    local epoch="$1"
    local period="$2"
    
    case "$period" in
        daily)   date -d "@$epoch" "+%Y-%m-%d" ;;
        weekly)  date -d "@$epoch" "+%Y-W%V" ;;
        monthly) date -d "@$epoch" "+%Y-%m" ;;
    esac
}

# Apply GFS retention policy
# Usage: apply_gfs_retention <array_of_snapshots> <keep_last> <keep_daily> <keep_weekly> <keep_monthly>
# Returns: array of snapshots to DELETE (in RETENTION_DELETE)
# Snapshots should be sorted by creation time (oldest first)
declare -a RETENTION_DELETE=()
declare -a RETENTION_KEEP=()

apply_gfs_retention() {
    local -n snapshots_ref=$1
    local keep_last="${2:-0}"
    local keep_daily="${3:-0}"
    local keep_weekly="${4:-0}"
    local keep_monthly="${5:-0}"
    
    RETENTION_DELETE=()
    RETENTION_KEEP=()
    
    local -A daily_kept=()
    local -A weekly_kept=()
    local -A monthly_kept=()
    local -a last_kept=()
    
    local total=${#snapshots_ref[@]}
    local now=$(date +%s)
    
    # Process from newest to oldest for "keep last N"
    local -a reversed=()
    for ((i=${#snapshots_ref[@]}-1; i>=0; i--)); do
        reversed+=("${snapshots_ref[$i]}")
    done
    
    for snapshot in "${reversed[@]}"; do
        local creation
        creation=$(get_snapshot_creation "$snapshot")
        local dominated=false
        
        # Keep last N
        if [[ $keep_last -gt 0 && ${#last_kept[@]} -lt $keep_last ]]; then
            last_kept+=("$snapshot")
            dominated=true
        fi
        
        # Keep daily
        if [[ $keep_daily -gt 0 ]]; then
            local day_key
            day_key=$(get_period_key "$creation" "daily")
            if [[ -z "${daily_kept[$day_key]:-}" && ${#daily_kept[@]} -lt $keep_daily ]]; then
                daily_kept[$day_key]="$snapshot"
                dominated=true
            fi
        fi
        
        # Keep weekly
        if [[ $keep_weekly -gt 0 ]]; then
            local week_key
            week_key=$(get_period_key "$creation" "weekly")
            if [[ -z "${weekly_kept[$week_key]:-}" && ${#weekly_kept[@]} -lt $keep_weekly ]]; then
                weekly_kept[$week_key]="$snapshot"
                dominated=true
            fi
        fi
        
        # Keep monthly
        if [[ $keep_monthly -gt 0 ]]; then
            local month_key
            month_key=$(get_period_key "$creation" "monthly")
            if [[ -z "${monthly_kept[$month_key]:-}" && ${#monthly_kept[@]} -lt $keep_monthly ]]; then
                monthly_kept[$month_key]="$snapshot"
                dominated=true
            fi
        fi
        
        if [[ "$dominated" == "true" ]]; then
            RETENTION_KEEP+=("$snapshot")
        else
            RETENTION_DELETE+=("$snapshot")
        fi
    done
}

# =============================================================================
# COMPRESSION HELPERS
# =============================================================================

# Supported compression types
COMPRESS_TYPES=("gzip" "zstd" "lz4" "none")

# Get compression command for type
get_compress_cmd() {
    local type="$1"
    case "$type" in
        gzip) echo "gzip -c" ;;
        zstd) echo "zstd -c -T0" ;;
        lz4)  echo "lz4 -c" ;;
        none) echo "cat" ;;
        *)    echo "cat" ;;
    esac
}

# Get decompression command for type
get_decompress_cmd() {
    local type="$1"
    case "$type" in
        gzip) echo "gzip -dc" ;;
        zstd) echo "zstd -dc" ;;
        lz4)  echo "lz4 -dc" ;;
        none) echo "cat" ;;
        *)    echo "cat" ;;
    esac
}

# Get file extension for compression type
get_compress_ext() {
    local type="$1"
    case "$type" in
        gzip) echo ".gz" ;;
        zstd) echo ".zst" ;;
        lz4)  echo ".lz4" ;;
        none) echo "" ;;
        *)    echo "" ;;
    esac
}

# Detect compression type from filename
detect_compression() {
    local filename="$1"
    case "$filename" in
        *.gz)  echo "gzip" ;;
        *.zst) echo "zstd" ;;
        *.lz4) echo "lz4" ;;
        *)     echo "none" ;;
    esac
}

# Check if compression tool is available
check_compress_tool() {
    local type="$1"
    case "$type" in
        gzip) command -v gzip &>/dev/null ;;
        zstd) command -v zstd &>/dev/null ;;
        lz4)  command -v lz4 &>/dev/null ;;
        none) return 0 ;;
        *)    return 1 ;;
    esac
}

# =============================================================================
# REMOTE/SSH HELPERS
# =============================================================================

# Parse remote URL
# Formats: user@host:path, ssh://user@host/path
# Sets: REMOTE_USER, REMOTE_HOST, REMOTE_PATH
parse_remote() {
    local remote="$1"
    
    if [[ "$remote" =~ ^ssh://([^@]+)@([^/]+)(/.*)$ ]]; then
        REMOTE_USER="${BASH_REMATCH[1]}"
        REMOTE_HOST="${BASH_REMATCH[2]}"
        REMOTE_PATH="${BASH_REMATCH[3]}"
    elif [[ "$remote" =~ ^([^@]+)@([^:]+):(.+)$ ]]; then
        REMOTE_USER="${BASH_REMATCH[1]}"
        REMOTE_HOST="${BASH_REMATCH[2]}"
        REMOTE_PATH="${BASH_REMATCH[3]}"
    elif [[ "$remote" =~ ^([^:]+):(.+)$ ]]; then
        REMOTE_USER=""
        REMOTE_HOST="${BASH_REMATCH[1]}"
        REMOTE_PATH="${BASH_REMATCH[2]}"
    else
        return 1
    fi
    return 0
}

# Build SSH command
build_ssh_cmd() {
    local user="${REMOTE_USER:-}"
    local host="$REMOTE_HOST"
    
    if [[ -n "$user" ]]; then
        echo "ssh ${user}@${host}"
    else
        echo "ssh ${host}"
    fi
}

# Test SSH connection
test_ssh_connection() {
    local ssh_cmd
    ssh_cmd=$(build_ssh_cmd)
    $ssh_cmd "echo ok" &>/dev/null
}

# =============================================================================
# PROGRESS HELPERS
# =============================================================================

# Check if pv is available
has_pv() {
    command -v pv &>/dev/null
}

# Build pipe with optional progress
# Usage: build_pipe_cmd <size_hint>
# Returns command to pipe through (pv or cat)
build_progress_pipe() {
    local size="${1:-}"
    
    if has_pv && [[ -n "$size" ]]; then
        echo "pv -s $size"
    elif has_pv; then
        echo "pv"
    else
        echo "cat"
    fi
}

# =============================================================================
# CRON HELPERS
# =============================================================================

CRON_TAG="zfsh"

# List all ZFSh cron entries
# Returns lines in format: id|type|pool|schedule|command
cron_list_entries() {
    crontab -l 2>/dev/null | grep -B1 "# ${CRON_TAG}:" | while read -r line; do
        if [[ "$line" =~ ^#\ ${CRON_TAG}: ]]; then
            # Parse metadata
            local meta="${line#\# ${CRON_TAG}:}"
            read -r schedule_line
            local schedule="${schedule_line%% /*}"
            local cmd="${schedule_line#* }"
            echo "${meta}|schedule=${schedule}|cmd=${cmd}"
        fi
    done
}

# Parse cron metadata line
# Usage: parse_cron_meta "id=1:type=snapshot:pool=default"
# Sets variables: CRON_ID, CRON_TYPE, CRON_POOL, etc.
parse_cron_meta() {
    local meta="$1"
    
    # Reset
    CRON_ID=""
    CRON_TYPE=""
    CRON_POOL=""
    CRON_EXTRA=""
    
    IFS=':' read -ra parts <<< "$meta"
    for part in "${parts[@]}"; do
        local key="${part%%=*}"
        local value="${part#*=}"
        case "$key" in
            id)   CRON_ID="$value" ;;
            type) CRON_TYPE="$value" ;;
            pool) CRON_POOL="$value" ;;
            *)    CRON_EXTRA+="${key}=${value}:" ;;
        esac
    done
}

# Get next available cron ID
cron_get_next_id() {
    local max_id=0
    while IFS='|' read -r meta _rest; do
        parse_cron_meta "$meta"
        if [[ -n "$CRON_ID" && "$CRON_ID" =~ ^[0-9]+$ && "$CRON_ID" -gt "$max_id" ]]; then
            max_id="$CRON_ID"
        fi
    done < <(cron_list_entries)
    echo "$((max_id + 1))"
}

# Add cron entry
# Usage: cron_add_entry <id> <type> <pool> <schedule> <command> [extra_meta]
cron_add_entry() {
    local id="$1"
    local type="$2"
    local pool="$3"
    local schedule="$4"
    local command="$5"
    local extra="${6:-}"
    
    local meta="id=${id}:type=${type}:pool=${pool}"
    [[ -n "$extra" ]] && meta+=":${extra}"
    
    local entry="# ${CRON_TAG}:${meta}
${schedule} ${command}"
    
    (crontab -l 2>/dev/null; echo "$entry") | crontab -
}

# Remove cron entry by ID
cron_remove_entry() {
    local target_id="$1"
    
    crontab -l 2>/dev/null | awk -v tag="$CRON_TAG" -v id="$target_id" '
        /^# '"$CRON_TAG"':/ {
            if ($0 ~ "id="id":") {
                getline  # skip next line (the actual cron command)
                next
            }
        }
        { print }
    ' | crontab -
}

# Build cron schedule string
# Usage: build_cron_schedule <frequency> [hour] [minute]
# frequency: hourly, daily, weekly, monthly, or custom cron expression
build_cron_schedule() {
    local freq="$1"
    local hour="${2:-2}"
    local minute="${3:-0}"
    
    case "$freq" in
        hourly)  echo "$minute * * * *" ;;
        daily)   echo "$minute $hour * * *" ;;
        weekly)  echo "$minute $hour * * 0" ;;
        monthly) echo "$minute $hour 1 * *" ;;
        *)       echo "$freq" ;;  # assume it's a custom cron expression
    esac
}
