---
title: Commands Overview
description: Overview of all ZFSh commands
---

# Commands Overview

ZFSh provides commands organized into functional groups. Each command supports `--help` for detailed usage information.

## Command Structure

```
zfsh <group> <command> [options]
```

Or using the interactive menu:

```
zfsh
```

## Command Groups

### Pool Management

Manage ZFS pools — create, monitor, expand, and check health.

| Command | Description |
|---------|-------------|
| `zfsh pool create` | Create new ZFS pool on sparse file |
| `zfsh pool info` | Display pool information |
| `zfsh pool expand` | Expand file-backed pool |
| `zfsh pool health` | Check pool health with recommendations |

[Full documentation](./pool.md)

### Snapshot Management

Create and manage ZFS snapshots with retention policies.

| Command | Description |
|---------|-------------|
| `zfsh snapshot create` | Create snapshot |
| `zfsh snapshot list` | List snapshots |
| `zfsh snapshot delete` | Delete snapshots |
| `zfsh snapshot rollback` | Rollback to snapshot |
| `zfsh snapshot cleanup` | Apply retention policy |

[Full documentation](./snapshot.md)

### Backup & Restore

Full and incremental backups with compression support.

| Command | Description |
|---------|-------------|
| `zfsh backup create` | Create backup file |
| `zfsh backup restore` | Restore from backup |
| `zfsh backup list` | List backup files |
| `zfsh backup verify` | Verify backup integrity |
| `zfsh backup cleanup` | Remove old backups |
| `zfsh backup send` | Send to remote server |

[Full documentation](./backup.md)

### Incus Integration

Initialize Incus container environment with ZFS backend.

| Command | Description |
|---------|-------------|
| `zfsh incus init` | Initialize Incus with ZFS pool |

[Full documentation](./incus.md)

### Scheduled Tasks

Manage automated ZFS operations via cron.

| Command | Description |
|---------|-------------|
| `zfsh cron add` | Add scheduled task |
| `zfsh cron list` | List scheduled tasks |
| `zfsh cron remove` | Remove task |
| `zfsh cron test` | Test run task |

[Full documentation](./cron.md)

## Global Options

These options are available for all commands:

| Option | Description |
|--------|-------------|
| `-j, --json` | Output in JSON format |
| `-q, --quiet` | Minimal output |
| `-l, --log FILE` | Log output to file |
| `-h, --help` | Show help message |

## Quick Examples

```bash
# Create a pool
zfsh pool create mypool -s 100G -c zstd

# Check health
zfsh pool health mypool

# Create snapshot
zfsh snapshot create mypool

# List snapshots as JSON
zfsh snapshot list --pool mypool --json

# Backup with compression
zfsh backup create mypool -c zstd

# Setup Incus
zfsh incus init -p mypool

# Schedule daily snapshots
zfsh cron add --type snapshot --pool mypool --daily
```

## Interactive Mode

Running `zfsh` without arguments opens the interactive menu:

```
======================================
  ZFSh v0.0.1
======================================

  1. Pool Management
  2. Snapshot Management
  3. Backup & Restore
  4. Health Check
  5. Incus Setup
  6. Scheduled Tasks

  q. Quit

Select option [1-6]:
```

Each menu option provides guided workflows for common operations.
