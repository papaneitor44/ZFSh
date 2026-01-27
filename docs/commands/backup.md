---
title: Backup & Restore
description: Full and incremental backups with compression support
---

# Backup & Restore

ZFSh provides comprehensive backup capabilities using ZFS send/receive, supporting local files, remote servers, and various compression methods.

## Commands

- [`zfsh backup create`](#backup-create) — Create backup file
- [`zfsh backup restore`](#backup-restore) — Restore from backup
- [`zfsh backup list`](#backup-list) — List backup files
- [`zfsh backup verify`](#backup-verify) — Verify backup integrity
- [`zfsh backup cleanup`](#backup-cleanup) — Remove old backups
- [`zfsh backup send`](#backup-send) — Send to remote server

---

## backup create

Create a backup file from a ZFS dataset or snapshot.

### Usage

```bash
zfsh backup create <dataset|snapshot> [options]
```

### Options

| Option | Description | Default |
|--------|-------------|---------|
| `-o, --output PATH` | Output directory | /root/backups/ |
| `-c, --compress TYPE` | Compression: gzip, zstd, lz4, none | zstd |
| `-i, --incremental` | Incremental from last snapshot | - |
| `--base SNAPSHOT` | Base snapshot for incremental | Auto-detect |
| `-r, --recursive` | Include children | - |
| `--progress` | Show progress (requires pv) | - |

### Output Filename Format

```
{pool}_{dataset}_{YYYYMMDD}_{HHMMSS}[_incr].zfs.{ext}
```

Examples:
- `default_20260127_143022.zfs.zst` (full, zstd)
- `default_containers_web_20260127_150000_incr.zfs.gz` (incremental, gzip)

### Examples

<details>
<summary>Create full backup with zstd compression</summary>

```bash
zfsh backup create default -c zstd
```

```
[INFO]  Creating snapshot for backup...
[OK]    Created snapshot: default@backup_20260127_143022
[INFO]  Creating backup: /root/backups/default_20260127_143022.zfs.zst
[OK]    Backup complete: /root/backups/default_20260127_143022.zfs.zst
[INFO]  Size: 1.2M, Duration: 3s
```

</details>

<details>
<summary>Create incremental backup</summary>

```bash
zfsh backup create default -i -c zstd
```

```
[INFO]  Creating snapshot for backup...
[OK]    Created snapshot: default@backup_20260127_150000
[INFO]  Incremental from: default@backup_20260127_143022
[INFO]  Creating backup: /root/backups/default_20260127_150000_incr.zfs.zst
[OK]    Backup complete: /root/backups/default_20260127_150000_incr.zfs.zst
[INFO]  Size: 24K, Duration: 1s
```

</details>

<details>
<summary>Backup specific snapshot</summary>

```bash
zfsh backup create default@before-upgrade -o /mnt/external/
```

</details>

<details>
<summary>Backup with progress bar</summary>

```bash
zfsh backup create default -c zstd --progress
```

```
[INFO]  Creating snapshot for backup...
[OK]    Created snapshot: default@backup_20260127_160000
[INFO]  Creating backup: /root/backups/default_20260127_160000.zfs.zst
 1.2GiB 0:00:45 [27.3MiB/s] [========================================>] 100%
[OK]    Backup complete
```

</details>

<details>
<summary>JSON output</summary>

```bash
zfsh backup create default -c zstd --json
```

```json
{
  "success": true,
  "file": "/root/backups/default_20260127_143022.zfs.zst",
  "size": 1258291,
  "size_human": "1.2M",
  "duration": 3,
  "snapshot": "default@backup_20260127_143022",
  "incremental": false,
  "compression": "zstd"
}
```

</details>

---

## backup restore

Restore a dataset from a backup file.

### Usage

```bash
zfsh backup restore <backup_file|-> <target_dataset> [options]
```

### Options

| Option | Description |
|--------|-------------|
| `-f, --force` | Force receive (destroy existing) |
| `--dry-run` | Test restore without applying |
| `--progress` | Show progress (requires pv) |

### Examples

<details>
<summary>Restore to new dataset</summary>

```bash
zfsh backup restore /root/backups/default_20260127_143022.zfs.zst default/restored
```

```
[INFO]  Restoring to: default/restored
[OK]    Restore complete
```

</details>

<details>
<summary>Force restore (overwrite existing)</summary>

```bash
zfsh backup restore backup.zfs.zst default/data -f
```

</details>

<details>
<summary>Restore from stdin (pipe)</summary>

```bash
cat backup.zfs.zst | zfsh backup restore - default/restored
```

</details>

<details>
<summary>Dry run to test restore</summary>

```bash
zfsh backup restore backup.zfs.zst default/test --dry-run
```

```
[INFO]  Restoring to: default/test
[INFO]  (Dry run mode)
[OK]    Restore complete
```

</details>

---

## backup list

List backup files in a directory.

### Usage

```bash
zfsh backup list [options]
```

### Options

| Option | Description | Default |
|--------|-------------|---------|
| `-d, --dir PATH` | Backup directory | /root/backups/ |
| `-p, --pool POOL` | Filter by pool name | - |
| `--sort FIELD` | Sort by: date, size, name | date |
| `-j, --json` | Output as JSON | - |

### Examples

<details>
<summary>List all backups</summary>

```bash
zfsh backup list
```

```
FILE                                          DATASET                   DATE              SIZE       TYPE   COMP
----                                          -------                   ----              ----       ----   ----
default_20260127_160000.zfs.zst               default                   20260127_160000   1.2M       full   zstd
default_20260127_150000_incr.zfs.zst          default                   20260127_150000   24K        incr   zstd
default_20260127_143022.zfs.zst               default                   20260127_143022   1.2M       full   zstd
default_containers_web_20260127.zfs.zst       default/containers/web    20260127_120000   45M        full   zstd
```

</details>

<details>
<summary>List backups sorted by size</summary>

```bash
zfsh backup list --sort size
```

</details>

<details>
<summary>Filter by pool</summary>

```bash
zfsh backup list --pool default
```

</details>

---

## backup verify

Verify backup file integrity.

### Usage

```bash
zfsh backup verify <backup_file> [options]
```

### Options

| Option | Description |
|--------|-------------|
| `--checksum` | Verify SHA256 checksum |
| `-v, --verbose` | Show detailed info |

### Examples

<details>
<summary>Verify backup</summary>

```bash
zfsh backup verify /root/backups/default_20260127_143022.zfs.zst
```

```
======================================
  Verifying: default_20260127_143022.zfs.zst
======================================

[OK]    File size: 1.2M
[OK]    Dataset: default
[OK]    Date: 20260127_143022
[OK]    Type: full
[OK]    Compression: zstd
[OK]    Checksum: OK

[OK]    Verification passed
```

</details>

<details>
<summary>Verbose verification with stream check</summary>

```bash
zfsh backup verify backup.zfs.zst -v
```

```
...
[INFO]  Verifying stream integrity...
[OK]    Stream: readable
```

</details>

---

## backup cleanup

Remove old backup files based on retention policy.

### Usage

```bash
zfsh backup cleanup [options]
```

### Options

| Option | Description | Default |
|--------|-------------|---------|
| `-d, --dir PATH` | Backup directory | /root/backups/ |
| `--keep-last N` | Keep last N backups per dataset | - |
| `--keep-daily N` | Keep N daily backups | - |
| `--keep-weekly N` | Keep N weekly backups | - |
| `--keep-monthly N` | Keep N monthly backups | - |
| `--older-than AGE` | Delete older than AGE | - |
| `--dry-run` | Show what would be deleted | - |
| `-y, --yes` | Skip confirmation | - |

### Examples

<details>
<summary>Keep last 10 backups</summary>

```bash
zfsh backup cleanup --keep-last 10 -y
```

</details>

<details>
<summary>Delete backups older than 30 days</summary>

```bash
zfsh backup cleanup --older-than 30d -y
```

```
======================================
  Cleanup Plan
======================================

Files to delete (3):
  default_20241215_020000.zfs.zst (1.1M)
  default_20241220_020000.zfs.zst (1.2M)
  default_20241225_020000.zfs.zst (1.1M)

[INFO]  Total space to free: 3.4M

[OK]    Deleted: default_20241215_020000.zfs.zst
[OK]    Deleted: default_20241220_020000.zfs.zst
[OK]    Deleted: default_20241225_020000.zfs.zst
[INFO]  Deleted 3 file(s)
```

</details>

<details>
<summary>Dry run cleanup</summary>

```bash
zfsh backup cleanup --older-than 7d --dry-run
```

</details>

---

## backup send

Send a backup directly to a remote server via SSH.

### Usage

```bash
zfsh backup send <dataset|snapshot> <remote> [options]
```

### Remote Formats

```
user@host:pool/dataset
ssh://user@host/pool/dataset
```

### Options

| Option | Description | Default |
|--------|-------------|---------|
| `-i, --incremental` | Incremental send | - |
| `--base SNAPSHOT` | Base for incremental | Auto-detect |
| `-c, --compress TYPE` | Compress stream | none |
| `--bandwidth LIMIT` | Limit bandwidth (e.g., 10M) | - |
| `--progress` | Show progress | - |
| `-r, --recursive` | Send children too | - |

### Examples

<details>
<summary>Send full backup to remote</summary>

```bash
zfsh backup send default backup@192.168.1.100:tank/backups
```

```
[INFO]  Remote: backup@192.168.1.100:tank/backups
[INFO]  Testing SSH connection...
[OK]    SSH connection OK
[INFO]  Creating snapshot for send...
[OK]    Created snapshot: default@backup_20260127_170000
[INFO]  Sending to 192.168.1.100:tank/backups...
[OK]    Send complete
```

</details>

<details>
<summary>Incremental send with compression</summary>

```bash
zfsh backup send default root@backup-server:tank/backups -i -c zstd --progress
```

```
[INFO]  Remote: root@backup-server:tank/backups
[INFO]  Testing SSH connection...
[OK]    SSH connection OK
[INFO]  Creating snapshot for send...
[OK]    Created snapshot: default@backup_20260127_180000
[INFO]  Incremental from: default@backup_20260127_170000
[INFO]  Sending to backup-server:tank/backups...
 24.5KiB 0:00:02 [12.2KiB/s] [==================================>] 100%
[OK]    Send complete
```

</details>

<details>
<summary>Send with bandwidth limit</summary>

```bash
zfsh backup send default remote:tank/backup --bandwidth 10M
```

</details>

---

## Compression Comparison

| Type | Speed | Ratio | CPU Usage | Recommended For |
|------|-------|-------|-----------|-----------------|
| `none` | Fastest | 1:1 | None | Local transfers, fast networks |
| `lz4` | Very fast | ~2:1 | Low | Fast backups, real-time |
| `gzip` | Medium | ~3:1 | Medium | Balanced, compatibility |
| `zstd` | Fast | ~3-4:1 | Low-Medium | Best overall (recommended) |

---

## Backup Strategy Tips

1. **Full + Incremental** — Weekly full, daily incremental
2. **Offsite copies** — Use `backup send` to remote servers
3. **Verify backups** — Periodically test restores
4. **Automate with cron** — See [Scheduled Tasks](./cron.md)
5. **Monitor disk space** — Use `backup cleanup` to manage retention

See [Backup Strategy Guide](../guides/backup-strategy.md) for detailed recommendations.
