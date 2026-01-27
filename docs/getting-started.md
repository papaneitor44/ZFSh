---
title: Getting Started
description: Install ZFSh and create your first ZFS pool
---

# Getting Started

This guide walks you through installing ZFSh and setting up your first ZFS pool.

## Prerequisites

### System Requirements

- Linux with ZFS support (Debian, Ubuntu, Proxmox, etc.)
- Bash 4.0 or later
- Root privileges

### Installing ZFS

If ZFS is not already installed:

```bash
# Debian/Ubuntu
apt update && apt install -y zfsutils-linux

# Verify installation
zfs --version
```

### Optional Dependencies

```bash
# Progress bars for long operations
apt install -y pv

# Compression tools (zstd recommended)
apt install -y zstd gzip lz4
```

## Installation

### Option 1: Clone Repository (Recommended)

```bash
git clone https://github.com/temasm/zfsh.git /opt/zfsh
cd /opt/zfsh
chmod +x zfsh *.sh

# Create symlink for global access
ln -s /opt/zfsh/zfsh /usr/local/bin/zfsh
```

### Option 2: Download Release

```bash
curl -L https://github.com/temasm/zfsh/archive/main.tar.gz | tar xz
mv zfsh-main /opt/zfsh
chmod +x /opt/zfsh/zfsh /opt/zfsh/*.sh
ln -s /opt/zfsh/zfsh /usr/local/bin/zfsh
```

### Verify Installation

```bash
zfsh --version
# Output: ZFSh v0.0.1
```

## Quick Start

### Step 1: Create a ZFS Pool

Create a 50GB pool with compression and deduplication:

```bash
zfsh pool create default -s 50G -c zstd -d on -y
```

<details>
<summary>Example output</summary>

```
======================================
  Create ZFS Pool
======================================

[INFO]  Creating sparse file: /var/lib/incus/disks/default.img (50G)
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

  Size:        50G
  Compression: zstd
  Dedup:       on
  Autotrim:    on
  Backend:     /var/lib/incus/disks/default.img
```

</details>

### Step 2: Verify Pool Status

```bash
zfsh pool info default
```

<details>
<summary>Example output</summary>

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
  Used:          780K (0%)
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
  Actual Size:   516K (sparse)
```

</details>

### Step 3: Initialize Incus (Optional)

If you plan to use Incus containers:

```bash
zfsh incus init -p default -y
```

<details>
<summary>Example output</summary>

```
======================================
  Incus Initialization with ZFS
======================================

Summary:
  ZFS pool:      default
  Storage name:  default
  Network:       incusbr0 (create new)

[INFO]  Applying Incus configuration...
[OK]    Incus initialized successfully
[INFO]  Verifying setup...
[OK]    Storage pool 'default' created
[OK]    Network 'incusbr0' available
[OK]    Default profile configured

Setup complete! You can now create containers:

  incus launch images:debian/12 my-container
  incus launch images:ubuntu/24.04 my-ubuntu
```

</details>

### Step 4: Create a Snapshot

```bash
zfsh snapshot create default
```

<details>
<summary>Example output</summary>

```
[INFO]  Creating snapshot: default@backup_20260127_143022
[OK]    Snapshot created: default@backup_20260127_143022
```

</details>

### Step 5: Set Up Automated Snapshots

```bash
# Daily snapshots at 2:00 AM
zfsh cron add --type snapshot --pool default --daily

# Cleanup with retention policy
zfsh cron add --type cleanup --pool default --daily \
    --keep-daily 7 --keep-weekly 4 --keep-monthly 3
```

## Next Steps

Now that you have a working ZFS setup, explore:

- [Pool Management](./commands/pool.md) — Learn about pool health checks and expansion
- [Snapshot Management](./commands/snapshot.md) — Master snapshot workflows
- [Backup Strategy](./guides/backup-strategy.md) — Design your backup system
- [Retention Policies](./guides/retention-policies.md) — Understand GFS retention

## Common Operations

### Check Pool Health

```bash
zfsh pool health default
```

### List Snapshots

```bash
zfsh snapshot list --pool default
```

### Create Backup

```bash
zfsh backup create default -c zstd
```

### Expand Pool

```bash
# Add 20GB to the pool
zfsh pool expand default -a 20G -y
```

## Troubleshooting

### "ZFS not installed"

Install ZFS utilities:

```bash
apt install -y zfsutils-linux
modprobe zfs
```

### "Permission denied"

ZFSh requires root privileges:

```bash
sudo zfsh pool create mypool -s 50G
```

### "No space left on device"

Check available disk space before creating pools:

```bash
df -h /var/lib/incus/disks/
```

## Getting Help

```bash
# General help
zfsh --help

# Command-specific help
zfsh pool --help
zfsh snapshot --help
zfsh backup --help
```
