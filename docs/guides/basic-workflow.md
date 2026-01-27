---
title: Basic Workflow
description: From pool creation to running containers
---

# Basic Workflow

This guide walks through a complete workflow from creating a ZFS pool to running containers with automated backups.

## Overview

1. Create ZFS pool
2. Initialize Incus
3. Deploy containers
4. Set up snapshots and backups
5. Monitor and maintain

---

## Step 1: Create ZFS Pool

Create a ZFS pool with compression and autotrim enabled:

```bash
zfsh pool create default -s 50G -c zstd -y
```

### Why These Options?

| Option | Reason |
|--------|--------|
| `-s 50G` | Start with 50GB, can expand later |
| `-c zstd` | Excellent compression ratio with low CPU usage |
| `-y` | Non-interactive for scripting |

### Verify Pool

```bash
zfsh pool info default
```

Expected output:
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
...
```

---

## Step 2: Initialize Incus

Set up Incus to use the ZFS pool:

```bash
zfsh incus init -p default -y
```

This creates:
- Storage pool `default` using ZFS
- Bridge network `incusbr0` with NAT
- Default profile with disk and network

### Verify Setup

```bash
# Check storage
incus storage list

# Check network
incus network list

# Check profile
incus profile show default
```

---

## Step 3: Deploy Containers

### Launch Your First Container

```bash
incus launch images:debian/12 web-server
```

### Wait for Startup

```bash
# Check status
incus list

# Wait for IP address
incus list web-server
```

Expected output:
```
+------------+---------+----------------------+------+-----------+-----------+
|    NAME    |  STATE  |         IPV4         | IPV6 |   TYPE    | SNAPSHOTS |
+------------+---------+----------------------+------+-----------+-----------+
| web-server | RUNNING | 10.10.10.100 (eth0) |      | CONTAINER | 0         |
+------------+---------+----------------------+------+-----------+-----------+
```

### Access Container

```bash
# Shell access
incus exec web-server -- bash

# Run command
incus exec web-server -- apt update
```

### Deploy More Containers

```bash
# Database server
incus launch images:debian/12 db-server

# Application server
incus launch images:ubuntu/24.04 app-server
```

---

## Step 4: Set Up Snapshots and Backups

### Manual Snapshot Before Changes

Before making significant changes:

```bash
zfsh snapshot create default -n before-changes
```

### Automated Daily Snapshots

```bash
zfsh cron add --type snapshot --pool default --daily
```

### Retention Policy

Clean up old snapshots automatically:

```bash
zfsh cron add --type cleanup --pool default --daily \
    --keep-daily 7 \
    --keep-weekly 4 \
    --keep-monthly 3
```

This keeps:
- Last 7 daily snapshots
- 4 weekly snapshots
- 3 monthly snapshots

### Weekly Backups

```bash
zfsh cron add --type backup --pool default --weekly \
    --compress zstd
```

### Verify Scheduled Tasks

```bash
zfsh cron list
```

---

## Step 5: Monitor and Maintain

### Daily Check

```bash
# Quick health check
zfsh pool health default -q
```

### Weekly Tasks

```bash
# Review snapshots
zfsh snapshot list --pool default

# Check backup files
zfsh backup list
```

### Monthly Tasks

```bash
# Full health check
zfsh pool health default

# Run scrub manually (or let cron do it)
zpool scrub default
```

### Expand Pool When Needed

```bash
# Check current usage
zfsh pool info default

# Add 20GB
zfsh pool expand default -a 20G -y
```

---

## Container Lifecycle

### Creating Snapshots

```bash
# Snapshot entire pool (all containers)
zfsh snapshot create default

# Snapshot specific container dataset
zfsh snapshot create default/containers/web-server
```

### Restoring Container

If something goes wrong:

```bash
# Stop container
incus stop web-server

# List snapshots
zfsh snapshot list default/containers/web-server

# Rollback
zfsh snapshot rollback default/containers/web-server@before-changes -y

# Start container
incus start web-server
```

### Cloning Container

```bash
# ZFS clone (instant, space-efficient)
incus copy web-server web-server-test
```

### Migrating Container

```bash
# Export
incus export web-server web-server-backup.tar.gz

# Import on another server
incus import web-server-backup.tar.gz
```

---

## Disaster Recovery

### Scenario: Container Corruption

1. Stop the container
2. Rollback to last good snapshot
3. Start the container

```bash
incus stop web-server
zfsh snapshot rollback default/containers/web-server@backup_20260126 -f -y
incus start web-server
```

### Scenario: Pool Issues

1. Check pool health
2. If degraded, investigate with `zpool status`
3. Restore from backup if necessary

```bash
# Check health
zfsh pool health default

# Detailed status
zpool status default

# If needed, restore from backup
zfsh backup restore /root/backups/default_20260120.zfs.zst default-restored
```

---

## Best Practices Summary

1. **Start with compression** — Always enable zstd
2. **Snapshot before changes** — Create named snapshots before updates
3. **Automate everything** — Use cron for snapshots, cleanup, backups
4. **Test restores** — Periodically verify backups work
5. **Monitor usage** — Keep pool below 80% capacity
6. **Offsite backups** — Use `backup send` for remote copies
7. **Monthly scrubs** — Detect corruption early
