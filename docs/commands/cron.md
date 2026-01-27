---
title: Scheduled Tasks
description: Manage automated ZFS operations via cron
---

# Scheduled Tasks

ZFSh provides easy management of automated ZFS operations through cron jobs. Schedule snapshots, backups, cleanup, and scrub operations with simple commands.

## Commands

- [`zfsh cron add`](#cron-add) — Add scheduled task
- [`zfsh cron list`](#cron-list) — List scheduled tasks
- [`zfsh cron remove`](#cron-remove) — Remove task
- [`zfsh cron test`](#cron-test) — Test run task

---

## cron add

Add a new scheduled task.

### Usage

```bash
zfsh cron add [options]
```

### Required Options

| Option | Description |
|--------|-------------|
| `--type TYPE` | Task type: snapshot, backup, cleanup, scrub |
| `--pool POOL` | Target ZFS pool |

### Schedule Options

| Option | Description | Default |
|--------|-------------|---------|
| `--hourly` | Run every hour | - |
| `--daily` | Run daily | Yes |
| `--weekly` | Run weekly (Sunday) | - |
| `--monthly` | Run monthly (1st) | - |
| `--cron "EXPR"` | Custom cron expression | - |
| `--time HH:MM` | Time to run | 02:00 |

### Backup Options (type: backup)

| Option | Description | Default |
|--------|-------------|---------|
| `--backup-dir PATH` | Backup directory | /root/backups |
| `--compress TYPE` | Compression type | zstd |
| `--remote DEST` | Remote destination | - |

### Retention Options (type: cleanup)

| Option | Description |
|--------|-------------|
| `--keep-last N` | Keep last N snapshots |
| `--keep-daily N` | Keep N daily snapshots |
| `--keep-weekly N` | Keep N weekly snapshots |
| `--keep-monthly N` | Keep N monthly snapshots |

### Examples

<details>
<summary>Daily snapshots at 2:00 AM</summary>

```bash
zfsh cron add --type snapshot --pool default --daily
```

```
[INFO]  Adding cron task #1: snapshot for default
[INFO]  Schedule: 0 2 * * *
[INFO]  Command: /opt/zfsh/zfs-snapshot.sh create default -r --prefix backup -q
[OK]    Task #1 added successfully

To view tasks: zfsh cron list
To remove:     zfsh cron remove --id 1
To test:       zfsh cron test --id 1 --dry-run
```

</details>

<details>
<summary>Cleanup with GFS retention</summary>

```bash
zfsh cron add --type cleanup --pool default --daily \
    --keep-daily 7 --keep-weekly 4 --keep-monthly 3
```

```
[INFO]  Adding cron task #2: cleanup for default
[INFO]  Schedule: 0 2 * * *
[INFO]  Command: /opt/zfsh/zfs-snapshot.sh cleanup default -y -q --keep-daily 7 --keep-weekly 4 --keep-monthly 3
[OK]    Task #2 added successfully
```

</details>

<details>
<summary>Weekly backup at 3:00 AM Sunday</summary>

```bash
zfsh cron add --type backup --pool default --weekly \
    --time 03:00 --compress zstd
```

```
[INFO]  Adding cron task #3: backup for default
[INFO]  Schedule: 0 3 * * 0
[INFO]  Command: /opt/zfsh/zfs-backup.sh create default -o /root/backups -c zstd -q
[OK]    Task #3 added successfully
```

</details>

<details>
<summary>Backup to remote server</summary>

```bash
zfsh cron add --type backup --pool default --daily \
    --remote backup@192.168.1.100:tank/backups
```

```
[INFO]  Adding cron task #4: backup for default
[INFO]  Schedule: 0 2 * * *
[INFO]  Command: /opt/zfsh/zfs-backup.sh send default backup@192.168.1.100:tank/backups -c zstd -q
[OK]    Task #4 added successfully
```

</details>

<details>
<summary>Monthly scrub</summary>

```bash
zfsh cron add --type scrub --pool default --monthly
```

```
[INFO]  Adding cron task #5: scrub for default
[INFO]  Schedule: 0 2 1 * *
[INFO]  Command: zpool scrub default
[OK]    Task #5 added successfully
```

</details>

<details>
<summary>Custom cron schedule (every 6 hours)</summary>

```bash
zfsh cron add --type snapshot --pool default --cron "0 */6 * * *"
```

</details>

---

## cron list

List all scheduled ZFS tasks.

### Usage

```bash
zfsh cron list [options]
```

### Options

| Option | Description |
|--------|-------------|
| `--type TYPE` | Filter by task type |
| `-j, --json` | Output as JSON |

### Examples

<details>
<summary>List all tasks</summary>

```bash
zfsh cron list
```

```
======================================
  Scheduled ZFS Tasks
======================================

ID   TYPE       POOL            SCHEDULE             COMMAND
--   ----       ----            --------             -------
1    snapshot   default         0 2 * * *            /opt/zfsh/zfs-snapshot.sh create defau...
2    cleanup    default         0 2 * * *            /opt/zfsh/zfs-snapshot.sh cleanup defa...
3    backup     default         0 3 * * 0            /opt/zfsh/zfs-backup.sh create default...
4    scrub      default         0 2 1 * *            zpool scrub default
```

</details>

<details>
<summary>Filter by type</summary>

```bash
zfsh cron list --type backup
```

</details>

<details>
<summary>JSON output</summary>

```bash
zfsh cron list --json
```

```json
{
  "tasks": [
    {
      "id": 1,
      "type": "snapshot",
      "pool": "default",
      "schedule": "0 2 * * *"
    },
    {
      "id": 2,
      "type": "cleanup",
      "pool": "default",
      "schedule": "0 2 * * *"
    }
  ]
}
```

</details>

---

## cron remove

Remove scheduled tasks.

### Usage

```bash
zfsh cron remove [options]
```

### Options

| Option | Description |
|--------|-------------|
| `--id ID` | Remove task by ID |
| `--type TYPE` | Remove all tasks of type |
| `--pool POOL` | Remove all tasks for pool |
| `--all` | Remove all ZFSh tasks |

### Examples

<details>
<summary>Remove by ID</summary>

```bash
zfsh cron remove --id 3
```

```
[INFO]  Will remove 1 task(s)
[OK]    Removed task #3 (backup for default)
[OK]    Removed 1 task(s)
```

</details>

<details>
<summary>Remove all snapshot tasks</summary>

```bash
zfsh cron remove --type snapshot
```

```
[INFO]  Will remove 2 task(s)
[OK]    Removed task #1 (snapshot for default)
[OK]    Removed task #5 (snapshot for backup)
[OK]    Removed 2 task(s)
```

</details>

<details>
<summary>Remove all tasks for a pool</summary>

```bash
zfsh cron remove --pool default
```

</details>

<details>
<summary>Remove all ZFSh tasks</summary>

```bash
zfsh cron remove --all
```

```
This will remove ALL ZFSh cron tasks (4 tasks)
Are you sure? [y/N]: y
[OK]    Removed task #1 (snapshot for default)
[OK]    Removed task #2 (cleanup for default)
[OK]    Removed task #3 (backup for default)
[OK]    Removed task #4 (scrub for default)
[OK]    Removed 4 task(s)
```

</details>

---

## cron test

Test run a scheduled task.

### Usage

```bash
zfsh cron test --id ID [options]
```

### Options

| Option | Description |
|--------|-------------|
| `--id ID` | Task ID to test |
| `--dry-run` | Show command without executing |

### Examples

<details>
<summary>Dry run (show what would happen)</summary>

```bash
zfsh cron test --id 2 --dry-run
```

```
======================================
  Test Task #2
======================================

Type: cleanup
Pool: default
Command: /opt/zfsh/zfs-snapshot.sh cleanup default -y -q --keep-daily 7 --keep-weekly 4 --keep-monthly 3

[INFO]  Dry run - command would be:
  /opt/zfsh/zfs-snapshot.sh cleanup default -y -q --keep-daily 7 --keep-weekly 4 --keep-monthly 3

Running with --dry-run:

======================================
  Cleanup Plan
======================================

Retention policy:
  Keep daily: 7
  Keep weekly: 4
  Keep monthly: 3

Snapshots to delete (0):
[INFO]  No snapshots to delete based on retention policy
```

</details>

<details>
<summary>Execute task immediately</summary>

```bash
zfsh cron test --id 1
```

```
======================================
  Test Task #1
======================================

Type: snapshot
Pool: default
Command: /opt/zfsh/zfs-snapshot.sh create default -r --prefix backup -q

[INFO]  Executing command...

[OK]    Snapshot created: default@backup_20260127_180000
[OK]    Task completed successfully
```

</details>

---

## Cron Schedule Reference

### Predefined Schedules

| Option | Cron Expression | Description |
|--------|-----------------|-------------|
| `--hourly` | `0 * * * *` | Every hour at :00 |
| `--daily` | `0 2 * * *` | Daily at 02:00 |
| `--weekly` | `0 2 * * 0` | Sunday at 02:00 |
| `--monthly` | `0 2 1 * *` | 1st of month at 02:00 |

### Custom Cron Expressions

Format: `minute hour day month weekday`

| Field | Values |
|-------|--------|
| minute | 0-59 |
| hour | 0-23 |
| day | 1-31 |
| month | 1-12 |
| weekday | 0-7 (0 and 7 are Sunday) |

Examples:
- `0 */6 * * *` — Every 6 hours
- `30 4 * * *` — Daily at 04:30
- `0 3 * * 1-5` — Weekdays at 03:00
- `0 0 1,15 * *` — 1st and 15th at midnight

---

## Recommended Schedule

A typical production setup:

```bash
# Hourly snapshots (keep 24)
zfsh cron add --type snapshot --pool default --hourly

# Daily cleanup with GFS retention
zfsh cron add --type cleanup --pool default --daily \
    --keep-daily 7 --keep-weekly 4 --keep-monthly 12

# Weekly full backup
zfsh cron add --type backup --pool default --weekly \
    --compress zstd

# Monthly scrub
zfsh cron add --type scrub --pool default --monthly
```

---

## How It Works

ZFSh stores task metadata in cron comments:

```bash
crontab -l
```

```
# zfsh:id=1:type=snapshot:pool=default:created=20260127
0 2 * * * /opt/zfsh/zfs-snapshot.sh create default -r --prefix backup -q
# zfsh:id=2:type=cleanup:pool=default:created=20260127
0 2 * * * /opt/zfsh/zfs-snapshot.sh cleanup default -y -q --keep-daily 7 --keep-weekly 4
```

This allows ZFSh to:
- Track and manage tasks by ID
- Filter tasks by type or pool
- Remove specific tasks without affecting others
