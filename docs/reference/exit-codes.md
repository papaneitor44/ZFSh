---
title: Exit Codes
description: ZFSh exit codes and their meanings
---

# Exit Codes

ZFSh scripts return standardized exit codes to indicate success, failure, or specific conditions.

## General Exit Codes

| Code | Name | Description |
|------|------|-------------|
| 0 | SUCCESS | Command completed successfully |
| 1 | ERROR | General error occurred |
| 2 | USAGE_ERROR | Invalid arguments or usage |
| 3 | NOT_FOUND | Resource not found (pool, dataset, snapshot) |
| 4 | PERMISSION_DENIED | Insufficient permissions (need root) |
| 5 | DEPENDENCY_MISSING | Required tool not installed |

## Command-Specific Codes

### Pool Commands

| Code | Command | Meaning |
|------|---------|---------|
| 0 | pool create | Pool created successfully |
| 1 | pool create | Failed to create pool |
| 3 | pool info | Pool not found |
| 0 | pool health | Pool is healthy (no warnings) |
| 1 | pool health | Pool is healthy with warnings |
| 2 | pool health | Pool has critical errors |

### Snapshot Commands

| Code | Command | Meaning |
|------|---------|---------|
| 0 | snapshot create | Snapshot created |
| 1 | snapshot create | Failed to create snapshot |
| 3 | snapshot rollback | Snapshot not found |
| 0 | snapshot cleanup | Cleanup completed |
| 1 | snapshot cleanup | Some deletions failed |

### Backup Commands

| Code | Command | Meaning |
|------|---------|---------|
| 0 | backup create | Backup created successfully |
| 1 | backup create | Backup failed |
| 0 | backup restore | Restore completed |
| 1 | backup restore | Restore failed |
| 3 | backup verify | Backup file not found |
| 1 | backup verify | Verification failed |

### Cron Commands

| Code | Command | Meaning |
|------|---------|---------|
| 0 | cron add | Task added |
| 1 | cron add | Failed to add task |
| 3 | cron test | Task ID not found |
| 0 | cron test | Task executed successfully |
| 1 | cron test | Task execution failed |

---

## Using Exit Codes in Scripts

### Basic Check

```bash
zfsh pool health default
if [ $? -eq 0 ]; then
    echo "Pool is healthy"
elif [ $? -eq 1 ]; then
    echo "Pool has warnings"
else
    echo "Pool has critical errors!"
fi
```

### Conditional Execution

```bash
# Only backup if pool is healthy
zfsh pool health default -q && zfsh backup create default

# Continue even if snapshot fails
zfsh snapshot create default || echo "Snapshot failed, continuing..."
```

### Capturing Exit Code

```bash
zfsh backup create default
EXIT_CODE=$?

case $EXIT_CODE in
    0) echo "Backup successful" ;;
    1) echo "Backup failed" ;;
    4) echo "Need root privileges" ;;
    5) echo "Missing compression tool" ;;
    *) echo "Unknown error: $EXIT_CODE" ;;
esac
```

---

## Exit Codes in JSON Output

When using `--json`, the exit code is also reflected in the output:

```bash
zfsh pool health default --json
```

Success (exit 0):
```json
{
  "pool": "default",
  "overall": "HEALTHY",
  "warnings": 0,
  "errors": 0,
  ...
}
```

Warning (exit 1):
```json
{
  "pool": "default",
  "overall": "WARNING",
  "warnings": 2,
  "errors": 0,
  ...
}
```

Error (exit 2):
```json
{
  "pool": "default",
  "overall": "CRITICAL",
  "warnings": 0,
  "errors": 3,
  ...
}
```

---

## Monitoring Integration

### Nagios/Icinga

```bash
#!/bin/bash
# check_zfs_health.sh

OUTPUT=$(zfsh pool health "$1" --json 2>&1)
EXIT_CODE=$?

case $EXIT_CODE in
    0) echo "OK - Pool $1 is healthy"; exit 0 ;;
    1) echo "WARNING - Pool $1 has warnings"; exit 1 ;;
    2) echo "CRITICAL - Pool $1 has errors"; exit 2 ;;
    *) echo "UNKNOWN - Could not check pool $1"; exit 3 ;;
esac
```

### Prometheus (with script exporter)

```bash
#!/bin/bash
# zfs_health_exporter.sh

for pool in $(zpool list -H -o name); do
    zfsh pool health "$pool" --json 2>/dev/null | \
    jq -r --arg pool "$pool" '
        "zfs_pool_healthy{pool=\"\($pool)\"} \(if .errors == 0 then 1 else 0 end)",
        "zfs_pool_warnings{pool=\"\($pool)\"} \(.warnings)",
        "zfs_pool_errors{pool=\"\($pool)\"} \(.errors)"
    '
done
```

---

## Troubleshooting by Exit Code

### Exit Code 4: Permission Denied

```bash
$ zfsh pool create test -s 10G
[ERROR] This operation requires root privileges

$ echo $?
4
```

**Solution**: Run with sudo or as root:
```bash
sudo zfsh pool create test -s 10G
```

### Exit Code 5: Dependency Missing

```bash
$ zfsh backup create default -c zstd
[ERROR] Compression tool 'zstd' not found

$ echo $?
5
```

**Solution**: Install missing tool:
```bash
apt install zstd
```

### Exit Code 3: Not Found

```bash
$ zfsh pool info nonexistent
[ERROR] Pool 'nonexistent' does not exist

$ echo $?
3
```

**Solution**: Check pool name:
```bash
zpool list
```
