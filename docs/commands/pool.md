---
title: Pool Management
description: Create, monitor, and manage ZFS pools
---

# Pool Management

ZFSh provides commands to create and manage file-backed ZFS pools. These are ideal for VPS and dedicated servers where you want ZFS features without dedicated disks.

## Commands

- [`zfsh pool create`](#pool-create) — Create new pool
- [`zfsh pool info`](#pool-info) — Display pool information
- [`zfsh pool expand`](#pool-expand) — Expand pool size
- [`zfsh pool health`](#pool-health) — Check pool health

---

## pool create

Create a new ZFS pool on a sparse file.

### Usage

```bash
zfsh pool create <name> [options]
```

### Arguments

| Argument | Description |
|----------|-------------|
| `name` | Pool name (required) |

### Options

| Option | Description | Default |
|--------|-------------|---------|
| `-s, --size SIZE` | Pool size (e.g., 50G, 100G) | 50G |
| `-p, --path PATH` | Sparse file location | /var/lib/incus/disks/ |
| `-c, --compression TYPE` | Compression: off, lz4, zstd, gzip | zstd |
| `-d, --dedup on\|off` | Enable deduplication | off |
| `-a, --autotrim on\|off` | Enable autotrim | on |
| `-y, --yes` | Skip confirmation | - |

### Examples

<details>
<summary>Create 50GB pool with defaults</summary>

```bash
zfsh pool create mypool -s 50G -y
```

```
======================================
  Create ZFS Pool
======================================

[INFO]  Creating sparse file: /var/lib/incus/disks/mypool.img (50G)
[OK]    Sparse file created
[INFO]  Creating ZFS pool: mypool
[OK]    Pool created successfully
[INFO]  Setting compression: zstd
[OK]    Compression enabled
[INFO]  Enabling autotrim
[OK]    Autotrim enabled

Pool 'mypool' created successfully!

  Size:        50G
  Compression: zstd
  Dedup:       off
  Autotrim:    on
  Backend:     /var/lib/incus/disks/mypool.img
```

</details>

<details>
<summary>Create pool with deduplication</summary>

```bash
zfsh pool create default -s 100G -c zstd -d on -y
```

```
[INFO]  Creating sparse file: /var/lib/incus/disks/default.img (100G)
[OK]    Sparse file created
[INFO]  Creating ZFS pool: default
[OK]    Pool created successfully
[INFO]  Setting compression: zstd
[OK]    Compression enabled
[INFO]  Setting dedup: on
[OK]    Deduplication enabled
[INFO]  Enabling autotrim
[OK]    Autotrim enabled

Pool 'default' created successfully!
```

</details>

<details>
<summary>Create pool in custom location</summary>

```bash
zfsh pool create backup -s 200G -p /mnt/storage/ -y
```

</details>

---

## pool info

Display detailed information about a ZFS pool.

### Usage

```bash
zfsh pool info [pool_name] [options]
```

### Options

| Option | Description |
|--------|-------------|
| `-a, --all` | Show all details including datasets |
| `-j, --json` | Output as JSON |

### Examples

<details>
<summary>Show pool information</summary>

```bash
zfsh pool info default
```

```
======================================
  ZFS Pool: default
======================================

Status
------
  State:         ONLINE
  Health:        ONLINE

Storage
-------
  Total:         49.5G
  Used:          1.52M (0%)
  Free:          49.5G
  Fragmentation: 0%
  Dedup Ratio:   1.00x

Properties
----------
  Compression:   zstd
  Dedup:         on
  Autotrim:      on

Backend
-------
  Type:          file
  Path:          /var/lib/incus/disks/default.img
  Actual Size:   548K (sparse)
```

</details>

<details>
<summary>Show pool info with datasets</summary>

```bash
zfsh pool info default -a
```

```
======================================
  ZFS Pool: default
======================================

Status
------
  State:         ONLINE
  Health:        ONLINE

Storage
-------
  Total:         49.5G
  Used:          2.89G (5%)
  Free:          46.6G
  Fragmentation: 1%
  Dedup Ratio:   1.00x

Properties
----------
  Compression:   zstd
  Dedup:         on
  Autotrim:      on

Backend
-------
  Type:          file
  Path:          /var/lib/incus/disks/default.img
  Actual Size:   1.8G (sparse)

Datasets
--------
  NAME                          USED    AVAIL   REFER
  default                       2.89G   46.6G   96K
  default/buckets               96K     46.6G   96K
  default/containers            1.44G   46.6G   96K
  default/containers/web        720M    46.6G   720M
  default/containers/db         720M    46.6G   720M
```

</details>

<details>
<summary>JSON output for scripting</summary>

```bash
zfsh pool info default --json
```

```json
{
  "pool": "default",
  "status": {
    "state": "ONLINE",
    "health": "ONLINE"
  },
  "storage": {
    "total": 53150220288,
    "total_human": "49.5G",
    "used": 1593344,
    "used_human": "1.52M",
    "free": 53148626944,
    "free_human": "49.5G",
    "capacity_percent": 0,
    "fragmentation_percent": 0,
    "dedup_ratio": 1.00
  },
  "properties": {
    "compression": "zstd",
    "dedup": "on",
    "autotrim": "on"
  },
  "backend": {
    "type": "file",
    "path": "/var/lib/incus/disks/default.img",
    "sparse_size": 561152
  },
  "datasets": []
}
```

</details>

---

## pool expand

Expand a file-backed ZFS pool.

### Usage

```bash
zfsh pool expand <pool_name> [options]
```

### Options

| Option | Description |
|--------|-------------|
| `-s, --size SIZE` | New total size (e.g., 100G) |
| `-a, --add SIZE` | Add size to current (e.g., +50G) |
| `-y, --yes` | Skip confirmation |

### Examples

<details>
<summary>Add 20GB to pool</summary>

```bash
zfsh pool expand default -a 20G -y
```

```
Pool:            default
Backend:         /var/lib/incus/disks/default.img
Current size:    49.5G
Current used:    1.52M
New size:        69.5G
Available space: 150G

[INFO]  Expanding sparse file to 69.5G...
[INFO]  Notifying ZFS of new size...
[OK]    Pool expanded to 69.5G
```

</details>

<details>
<summary>Expand to specific size</summary>

```bash
zfsh pool expand default -s 100G -y
```

</details>

---

## pool health

Check pool health and get recommendations.

### Usage

```bash
zfsh pool health [pool_name] [options]
```

### Options

| Option | Description |
|--------|-------------|
| `-a, --all` | Check all pools |
| `-q, --quiet` | Only show problems |
| `-j, --json` | Output as JSON |

### Checks Performed

- Pool status (ONLINE/DEGRADED/FAULTED)
- I/O errors (read/write/checksum)
- Last scrub time
- Compression status
- Deduplication status and RAM usage
- Capacity usage (warning at 80%)
- Fragmentation level
- Autotrim status

### Examples

<details>
<summary>Check pool health</summary>

```bash
zfsh pool health default
```

```
======================================
  ZFS Health Check: default
======================================

[OK]    Pool status: ONLINE
[OK]    I/O errors: R:0 W:0 C:0
[WARN]  Last scrub: never
        No scrub has been performed. Recommend: 'zpool scrub default'
[OK]    Compression: zstd (ratio: 1.00x)
[OK]    Dedup: on (ratio: 1.00x, DDT: ~0B)
[OK]    Capacity: 0%
[OK]    Fragmentation: 0%
[OK]    Autotrim: on

─────────────────────────────────────
Overall: HEALTHY (1 warnings)
```

</details>

<details>
<summary>Check all pools</summary>

```bash
zfsh pool health --all
```

</details>

<details>
<summary>Only show problems</summary>

```bash
zfsh pool health default -q
```

```
[WARN]  Last scrub: never
        No scrub has been performed. Recommend: 'zpool scrub default'

─────────────────────────────────────
Overall: HEALTHY (1 warnings)
```

</details>

### Exit Codes

| Code | Meaning |
|------|---------|
| 0 | Healthy (no warnings or errors) |
| 1 | Healthy with warnings |
| 2 | Critical errors detected |

---

## Understanding Sparse Files

ZFSh creates pools on sparse files, which only consume disk space for actual data:

```
Pool Size:    50G (virtual)
Actual Size:  548K (on disk)
```

This allows you to:
- Over-provision storage
- Grow pools without downtime
- Use ZFS features without dedicated disks

### Checking Actual Usage

```bash
# Virtual size (what ZFS sees)
zpool get size mypool

# Actual disk usage
du -h /var/lib/incus/disks/mypool.img
```

## Best Practices

1. **Enable compression** — zstd provides excellent compression with low CPU overhead
2. **Consider dedup carefully** — Requires ~5GB RAM per 1TB of data
3. **Monitor capacity** — ZFS performance degrades above 80% usage
4. **Regular scrubs** — Run `zpool scrub` monthly to detect corruption
5. **Enable autotrim** — Reclaims space on the underlying filesystem
