---
title: CLI Reference
description: Complete command-line reference for ZFSh
---

# CLI Reference

Complete reference for all ZFSh commands, options, and arguments.

## General Usage

```
zfsh [--version] [--help]
zfsh <command> <subcommand> [options] [arguments]
```

## Global Options

Available for all commands:

| Option | Short | Description |
|--------|-------|-------------|
| `--help` | `-h` | Show help message |
| `--json` | `-j` | Output in JSON format |
| `--quiet` | `-q` | Minimal output |
| `--log FILE` | `-l` | Log output to file |

---

## Pool Commands

### zfsh pool create

Create a new ZFS pool on a sparse file.

```
zfsh pool create <name> [options]
```

| Option | Short | Description | Default |
|--------|-------|-------------|---------|
| `--size SIZE` | `-s` | Pool size (e.g., 50G) | 50G |
| `--path PATH` | `-p` | Sparse file location | /var/lib/incus/disks/ |
| `--compression TYPE` | `-c` | off, lz4, zstd, gzip | zstd |
| `--dedup on\|off` | `-d` | Enable deduplication | off |
| `--autotrim on\|off` | `-a` | Enable autotrim | on |
| `--yes` | `-y` | Skip confirmation | - |

### zfsh pool info

Display pool information.

```
zfsh pool info [pool_name] [options]
```

| Option | Short | Description |
|--------|-------|-------------|
| `--all` | `-a` | Show all details including datasets |
| `--json` | `-j` | Output as JSON |

### zfsh pool expand

Expand a file-backed pool.

```
zfsh pool expand <pool_name> [options]
```

| Option | Short | Description |
|--------|-------|-------------|
| `--size SIZE` | `-s` | New total size |
| `--add SIZE` | `-a` | Add to current size |
| `--yes` | `-y` | Skip confirmation |

### zfsh pool health

Check pool health.

```
zfsh pool health [pool_name] [options]
```

| Option | Short | Description |
|--------|-------|-------------|
| `--all` | `-a` | Check all pools |
| `--quiet` | `-q` | Only show problems |
| `--json` | `-j` | Output as JSON |

---

## Snapshot Commands

### zfsh snapshot create

Create a snapshot.

```
zfsh snapshot create <dataset> [options]
```

| Option | Short | Description | Default |
|--------|-------|-------------|---------|
| `--name NAME` | `-n` | Snapshot name | Auto-generated |
| `--recursive` | `-r` | Recursive snapshots | - |
| `--prefix PREFIX` | `-p` | Name prefix | backup |
| `--yes` | `-y` | Skip confirmation | - |

### zfsh snapshot list

List snapshots.

```
zfsh snapshot list [dataset] [options]
```

| Option | Short | Description |
|--------|-------|-------------|
| `--pool POOL` | `-p` | Filter by pool |
| `--age AGE` | `-a` | Filter by max age (e.g., 7d) |
| `--prefix PREFIX` | | Filter by name prefix |
| `--sort FIELD` | | Sort: creation, name, used |
| `--json` | `-j` | Output as JSON |

### zfsh snapshot delete

Delete snapshots.

```
zfsh snapshot delete <dataset|snapshot> [options]
```

| Option | Short | Description |
|--------|-------|-------------|
| `--name NAME` | `-n` | Delete by name |
| `--recursive` | `-r` | Delete recursively |
| `--older-than AGE` | | Delete older than AGE |
| `--prefix PREFIX` | | Delete with prefix |
| `--dry-run` | | Preview deletion |
| `--yes` | `-y` | Skip confirmation |

### zfsh snapshot rollback

Rollback to a snapshot.

```
zfsh snapshot rollback <snapshot> [options]
```

| Option | Short | Description |
|--------|-------|-------------|
| `--recursive` | `-r` | Rollback children |
| `--force` | `-f` | Destroy newer snapshots |
| `--yes` | `-y` | Skip confirmation |

### zfsh snapshot cleanup

Apply retention policy.

```
zfsh snapshot cleanup <dataset> [options]
```

| Option | Description |
|--------|-------------|
| `--keep-last N` | Keep last N snapshots |
| `--keep-daily N` | Keep N daily snapshots |
| `--keep-weekly N` | Keep N weekly snapshots |
| `--keep-monthly N` | Keep N monthly snapshots |
| `--older-than AGE` | Delete older than AGE |
| `--recursive` | Apply to children |
| `--prefix PREFIX` | Apply to prefix only |
| `--dry-run` | Preview cleanup |
| `--yes` | Skip confirmation |

---

## Backup Commands

### zfsh backup create

Create a backup file.

```
zfsh backup create <dataset|snapshot> [options]
```

| Option | Short | Description | Default |
|--------|-------|-------------|---------|
| `--output PATH` | `-o` | Output directory | /root/backups/ |
| `--compress TYPE` | `-c` | gzip, zstd, lz4, none | zstd |
| `--incremental` | `-i` | Incremental backup | - |
| `--base SNAPSHOT` | | Base for incremental | Auto-detect |
| `--recursive` | `-r` | Include children | - |
| `--progress` | | Show progress | - |

### zfsh backup restore

Restore from backup.

```
zfsh backup restore <file|-> <target> [options]
```

| Option | Short | Description |
|--------|-------|-------------|
| `--force` | `-f` | Overwrite existing |
| `--dry-run` | | Test without applying |
| `--progress` | | Show progress |

### zfsh backup list

List backup files.

```
zfsh backup list [options]
```

| Option | Short | Description | Default |
|--------|-------|-------------|---------|
| `--dir PATH` | `-d` | Backup directory | /root/backups/ |
| `--pool POOL` | `-p` | Filter by pool | - |
| `--sort FIELD` | | Sort: date, size, name | date |
| `--json` | `-j` | Output as JSON | - |

### zfsh backup verify

Verify backup integrity.

```
zfsh backup verify <file> [options]
```

| Option | Short | Description |
|--------|-------|-------------|
| `--checksum` | | Verify SHA256 |
| `--verbose` | `-v` | Detailed output |

### zfsh backup cleanup

Remove old backups.

```
zfsh backup cleanup [options]
```

| Option | Short | Description | Default |
|--------|-------|-------------|---------|
| `--dir PATH` | `-d` | Backup directory | /root/backups/ |
| `--keep-last N` | | Keep last N | - |
| `--keep-daily N` | | Keep N daily | - |
| `--keep-weekly N` | | Keep N weekly | - |
| `--keep-monthly N` | | Keep N monthly | - |
| `--older-than AGE` | | Delete older than | - |
| `--dry-run` | | Preview deletion | - |
| `--yes` | `-y` | Skip confirmation | - |

### zfsh backup send

Send to remote server.

```
zfsh backup send <dataset|snapshot> <remote> [options]
```

Remote format: `user@host:pool/dataset`

| Option | Short | Description | Default |
|--------|-------|-------------|---------|
| `--incremental` | `-i` | Incremental send | - |
| `--base SNAPSHOT` | | Base for incremental | Auto-detect |
| `--compress TYPE` | `-c` | Stream compression | none |
| `--bandwidth LIMIT` | | Limit (e.g., 10M) | - |
| `--progress` | | Show progress | - |
| `--recursive` | `-r` | Send children | - |

---

## Incus Commands

### zfsh incus init

Initialize Incus with ZFS pool.

```
zfsh incus init [options]
```

| Option | Short | Description | Default |
|--------|-------|-------------|---------|
| `--pool NAME` | `-p` | ZFS pool name | default |
| `--storage NAME` | `-s` | Incus storage name | Same as pool |
| `--network NAME` | `-n` | Bridge network name | incusbr0 |
| `--network-ipv4 CIDR` | | IPv4 subnet | Auto |
| `--no-network` | | Skip network | - |
| `--yes` | `-y` | Skip confirmation | - |

---

## Cron Commands

### zfsh cron add

Add scheduled task.

```
zfsh cron add [options]
```

**Required:**

| Option | Description |
|--------|-------------|
| `--type TYPE` | snapshot, backup, cleanup, scrub |
| `--pool POOL` | Target pool |

**Schedule:**

| Option | Description | Default |
|--------|-------------|---------|
| `--hourly` | Run hourly | - |
| `--daily` | Run daily | Yes |
| `--weekly` | Run weekly (Sunday) | - |
| `--monthly` | Run monthly (1st) | - |
| `--cron "EXPR"` | Custom cron expression | - |
| `--time HH:MM` | Time to run | 02:00 |

**Backup options (type: backup):**

| Option | Description | Default |
|--------|-------------|---------|
| `--backup-dir PATH` | Backup directory | /root/backups |
| `--compress TYPE` | Compression | zstd |
| `--remote DEST` | Remote destination | - |

**Retention options (type: cleanup):**

| Option | Description |
|--------|-------------|
| `--keep-last N` | Keep last N |
| `--keep-daily N` | Keep N daily |
| `--keep-weekly N` | Keep N weekly |
| `--keep-monthly N` | Keep N monthly |

### zfsh cron list

List scheduled tasks.

```
zfsh cron list [options]
```

| Option | Description |
|--------|-------------|
| `--type TYPE` | Filter by type |
| `--json` | Output as JSON |

### zfsh cron remove

Remove scheduled tasks.

```
zfsh cron remove [options]
```

| Option | Description |
|--------|-------------|
| `--id ID` | Remove by ID |
| `--type TYPE` | Remove all of type |
| `--pool POOL` | Remove all for pool |
| `--all` | Remove all ZFSh tasks |

### zfsh cron test

Test run a task.

```
zfsh cron test --id ID [options]
```

| Option | Description |
|--------|-------------|
| `--id ID` | Task ID |
| `--dry-run` | Show without executing |

---

## Size Formats

All size options accept:

| Format | Example | Bytes |
|--------|---------|-------|
| Bytes | 1024 | 1024 |
| Kilobytes | 10K | 10,240 |
| Megabytes | 100M | 104,857,600 |
| Gigabytes | 50G | 53,687,091,200 |
| Terabytes | 1T | 1,099,511,627,776 |

## Age Formats

All age options accept:

| Format | Example | Description |
|--------|---------|-------------|
| Days | 7d | 7 days |
| Weeks | 2w | 2 weeks |
| Months | 3m | 3 months |
| Hours | 24h | 24 hours |

---

## Environment Variables

| Variable | Description | Default |
|----------|-------------|---------|
| `ZFSH_BACKUP_DIR` | Default backup directory | /root/backups |
| `ZFSH_SNAPSHOT_PREFIX` | Default snapshot prefix | backup |
| `ZFSH_COMPRESS` | Default compression | zstd |

---

## Configuration Files

ZFSh reads configuration from:

1. `/etc/zfsh/config` (system-wide)
2. `~/.config/zfsh/config` (user)
3. `./.zfsh` (project-local)

Example config:
```bash
# /etc/zfsh/config
BACKUP_DIR="/mnt/backups"
SNAPSHOT_PREFIX="auto"
COMPRESS_TYPE="zstd"
```
