---
title: Snapshot Management
description: Create and manage ZFS snapshots with retention policies
---

# Snapshot Management

ZFSh provides comprehensive snapshot management including creation, listing, deletion, rollback, and automated cleanup with GFS (Grandfather-Father-Son) retention policies.

## Commands

- [`zfsh snapshot create`](#snapshot-create) — Create snapshot
- [`zfsh snapshot list`](#snapshot-list) — List snapshots
- [`zfsh snapshot delete`](#snapshot-delete) — Delete snapshots
- [`zfsh snapshot rollback`](#snapshot-rollback) — Rollback to snapshot
- [`zfsh snapshot cleanup`](#snapshot-cleanup) — Apply retention policy

---

## snapshot create

Create a new ZFS snapshot.

### Usage

```bash
zfsh snapshot create <dataset> [options]
```

### Arguments

| Argument | Description |
|----------|-------------|
| `dataset` | Dataset to snapshot (required) |

### Options

| Option | Description | Default |
|--------|-------------|---------|
| `-n, --name NAME` | Snapshot name | Auto-generated |
| `-r, --recursive` | Create recursive snapshots | - |
| `-p, --prefix PREFIX` | Name prefix | backup |
| `-y, --yes` | Skip confirmation | - |

### Snapshot Naming

Auto-generated names follow the pattern:
```
{prefix}_{YYYYMMDD}_{HHMMSS}
```

Example: `backup_20260127_143022`

### Examples

<details>
<summary>Create snapshot with auto-generated name</summary>

```bash
zfsh snapshot create default
```

```
[INFO]  Creating snapshot: default@backup_20260127_143022
[OK]    Snapshot created: default@backup_20260127_143022
```

</details>

<details>
<summary>Create snapshot with custom name</summary>

```bash
zfsh snapshot create default/containers/web -n before-upgrade
```

```
[INFO]  Creating snapshot: default/containers/web@before-upgrade
[OK]    Snapshot created: default/containers/web@before-upgrade
```

</details>

<details>
<summary>Create recursive snapshots</summary>

```bash
zfsh snapshot create default -r --prefix hourly
```

```
[INFO]  Creating snapshot: default@hourly_20260127_143022
[OK]    Snapshot created: default@hourly_20260127_143022
```

This creates snapshots for `default` and all child datasets.

</details>

---

## snapshot list

List ZFS snapshots.

### Usage

```bash
zfsh snapshot list [dataset] [options]
```

### Options

| Option | Description |
|--------|-------------|
| `-p, --pool POOL` | Filter by pool |
| `-a, --age AGE` | Filter by max age (e.g., 7d, 2w) |
| `--prefix PREFIX` | Filter by name prefix |
| `--sort FIELD` | Sort by: creation, name, used |
| `-j, --json` | Output as JSON |

### Examples

<details>
<summary>List all snapshots</summary>

```bash
zfsh snapshot list
```

```
NAME                                       CREATION             USED       REFER
----                                       --------             ----       -----
default@backup_20260125_020000             Mon Jan 25 02:00     64K        96K
default@backup_20260126_020000             Tue Jan 26 02:00     64K        96K
default@backup_20260127_020000             Wed Jan 27 02:00     0B         96K
default/containers/web@backup_20260127     Wed Jan 27 14:30     0B         720M
```

</details>

<details>
<summary>List snapshots for specific pool</summary>

```bash
zfsh snapshot list --pool default
```

</details>

<details>
<summary>List snapshots from last 7 days</summary>

```bash
zfsh snapshot list --age 7d
```

</details>

<details>
<summary>List snapshots with specific prefix</summary>

```bash
zfsh snapshot list --prefix hourly
```

</details>

<details>
<summary>JSON output</summary>

```bash
zfsh snapshot list --pool default --json
```

```json
{
  "snapshots": [
    {
      "name": "default@backup_20260127_020000",
      "creation": "Wed Jan 27 02:00 2026",
      "used": "0B",
      "refer": "96K"
    }
  ]
}
```

</details>

---

## snapshot delete

Delete ZFS snapshots.

### Usage

```bash
zfsh snapshot delete <dataset|snapshot> [options]
```

### Options

| Option | Description |
|--------|-------------|
| `-n, --name NAME` | Delete specific snapshot by name |
| `-r, --recursive` | Delete recursively |
| `--older-than AGE` | Delete snapshots older than AGE |
| `--prefix PREFIX` | Delete only with this prefix |
| `--dry-run` | Show what would be deleted |
| `-y, --yes` | Skip confirmation |

### Examples

<details>
<summary>Delete specific snapshot</summary>

```bash
zfsh snapshot delete default@backup_20260120_020000 -y
```

```
Snapshots to delete (1):
  default@backup_20260120_020000
[OK]    Deleted: default@backup_20260120_020000
[INFO]  Deleted: 1, Failed: 0
```

</details>

<details>
<summary>Delete snapshots older than 30 days</summary>

```bash
zfsh snapshot delete default --older-than 30d -y
```

```
Snapshots to delete (5):
  default@backup_20241215_020000
  default@backup_20241220_020000
  default@backup_20241225_020000
  default@backup_20241228_020000
  default@backup_20260101_020000

[OK]    Deleted: default@backup_20241215_020000
[OK]    Deleted: default@backup_20241220_020000
[OK]    Deleted: default@backup_20241225_020000
[OK]    Deleted: default@backup_20241228_020000
[OK]    Deleted: default@backup_20260101_020000
[INFO]  Deleted: 5, Failed: 0
```

</details>

<details>
<summary>Dry run - see what would be deleted</summary>

```bash
zfsh snapshot delete default --older-than 7d --dry-run
```

```
Snapshots to delete (3):
  default@backup_20260118_020000
  default@backup_20260119_020000
  default@backup_20260120_020000
[INFO]  Dry run - no changes made
```

</details>

---

## snapshot rollback

Rollback a dataset to a previous snapshot.

### Usage

```bash
zfsh snapshot rollback <snapshot> [options]
```

### Options

| Option | Description |
|--------|-------------|
| `-r, --recursive` | Rollback children too |
| `-f, --force` | Destroy intermediate snapshots |
| `-y, --yes` | Skip confirmation |

### Examples

<details>
<summary>Rollback to snapshot</summary>

```bash
zfsh snapshot rollback default/containers/web@before-upgrade -y
```

```
[INFO]  Rolling back to: default/containers/web@before-upgrade
[OK]    Rollback complete
```

</details>

<details>
<summary>Force rollback (destroys newer snapshots)</summary>

```bash
zfsh snapshot rollback default@backup_20260120 -f -y
```

```
Warning: The following snapshots are newer and will be destroyed:
default@backup_20260125
default@backup_20260126
default@backup_20260127

[INFO]  Rolling back to: default@backup_20260120
[OK]    Rollback complete
```

</details>

---

## snapshot cleanup

Apply retention policy to automatically delete old snapshots.

### Usage

```bash
zfsh snapshot cleanup <dataset> [options]
```

### Retention Options

| Option | Description |
|--------|-------------|
| `--keep-last N` | Keep last N snapshots |
| `--keep-daily N` | Keep N daily snapshots (one per day) |
| `--keep-weekly N` | Keep N weekly snapshots (one per week) |
| `--keep-monthly N` | Keep N monthly snapshots (one per month) |
| `--older-than AGE` | Delete older than AGE |

### Other Options

| Option | Description |
|--------|-------------|
| `-r, --recursive` | Apply to children |
| `--prefix PREFIX` | Apply only to snapshots with prefix |
| `--dry-run` | Show what would be deleted |
| `-y, --yes` | Skip confirmation |

### Examples

<details>
<summary>Keep last 10 snapshots</summary>

```bash
zfsh snapshot cleanup default --keep-last 10 -y
```

</details>

<details>
<summary>GFS retention policy</summary>

```bash
zfsh snapshot cleanup default \
    --keep-daily 7 \
    --keep-weekly 4 \
    --keep-monthly 3 \
    -y
```

```
======================================
  Cleanup Plan
======================================

Retention policy:
  Keep daily: 7
  Keep weekly: 4
  Keep monthly: 3

Snapshots to delete (12):
  default@backup_20241201_020000 (age: 57 days)
  default@backup_20241205_020000 (age: 53 days)
  default@backup_20241210_020000 (age: 48 days)
  ...

[OK]    Deleted: default@backup_20241201_020000
[OK]    Deleted: default@backup_20241205_020000
...

Summary: Deleted 12, Failed 0
```

</details>

<details>
<summary>Dry run to preview cleanup</summary>

```bash
zfsh snapshot cleanup default \
    --keep-daily 7 \
    --keep-weekly 4 \
    --dry-run
```

</details>

<details>
<summary>Cleanup specific prefix only</summary>

```bash
zfsh snapshot cleanup default --prefix hourly --keep-last 24 -y
```

</details>

---

## Understanding GFS Retention

GFS (Grandfather-Father-Son) is a rotation scheme that keeps:

- **Daily** (Son) — Recent snapshots, one per day
- **Weekly** (Father) — Older snapshots, one per week
- **Monthly** (Grandfather) — Archive snapshots, one per month

### Example: `--keep-daily 7 --keep-weekly 4 --keep-monthly 3`

Over time, this keeps:
- Last 7 daily snapshots (past week)
- 4 weekly snapshots (past month)
- 3 monthly snapshots (past quarter)

Total: ~14 snapshots covering 3+ months

### How Selection Works

When selecting which snapshot to keep for a period:
1. The **most recent** snapshot in that period is kept
2. Other snapshots in the same period are candidates for deletion

See [Retention Policies Guide](../guides/retention-policies.md) for detailed examples.

---

## Best Practices

1. **Use meaningful prefixes** — Separate `hourly`, `daily`, `backup` snapshots
2. **Automate with cron** — See [Scheduled Tasks](./cron.md)
3. **Test rollback** — Verify snapshots work before you need them
4. **Use --dry-run** — Preview cleanup before execution
5. **Monitor snapshot count** — Too many snapshots can impact performance
