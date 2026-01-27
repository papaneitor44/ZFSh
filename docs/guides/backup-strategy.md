---
title: Backup Strategy
description: Designing a reliable backup system with ZFSh
---

# Backup Strategy

This guide covers designing and implementing a reliable backup strategy using ZFSh.

## Backup Types

### Snapshots vs. Backups

| Feature | Snapshots | Backups |
|---------|-----------|---------|
| **Location** | Same pool | External file/server |
| **Protection** | User errors, quick rollback | Hardware failure, disaster |
| **Speed** | Instant | Minutes to hours |
| **Space** | Shared (copy-on-write) | Full copy |
| **Recovery** | Instant | Restore required |

**Best Practice**: Use both. Snapshots for quick recovery, backups for disaster protection.

### Full vs. Incremental Backups

| Type | Contains | Size | Use Case |
|------|----------|------|----------|
| **Full** | Complete dataset | Large | Weekly baseline, new systems |
| **Incremental** | Changes since last | Small | Daily updates |

---

## Backup Strategies

### Strategy 1: Simple (Small Deployments)

For personal servers or small deployments:

```bash
# Daily full backup
zfsh cron add --type backup --pool default --daily \
    --compress zstd
```

**Pros**: Simple, easy to restore
**Cons**: Uses more storage

### Strategy 2: Full + Incremental (Recommended)

Weekly full backup with daily incrementals:

```bash
# Weekly full backup (Sunday 3 AM)
zfsh cron add --type backup --pool default --weekly \
    --time 03:00 --compress zstd

# Daily incremental (2 AM, Mon-Sat)
# Manual setup in crontab for specific days:
# 0 2 * * 1-6 /opt/zfsh/zfs-backup.sh create default -i -c zstd -q
```

**Pros**: Storage efficient, fast dailies
**Cons**: Restore requires full + incrementals

### Strategy 3: 3-2-1 Rule (Production)

- **3** copies of data
- **2** different media types
- **1** offsite copy

```bash
# Local snapshots (hourly)
zfsh cron add --type snapshot --pool default --hourly

# Local backup file (daily)
zfsh cron add --type backup --pool default --daily \
    --compress zstd

# Remote backup (daily)
zfsh cron add --type backup --pool default --daily \
    --remote backup@offsite:tank/backups
```

---

## Remote Backups

### Setup SSH Key Authentication

```bash
# Generate key (on source server)
ssh-keygen -t ed25519 -f ~/.ssh/backup_key -N ""

# Copy to destination
ssh-copy-id -i ~/.ssh/backup_key backup@offsite-server
```

### Send to Remote Server

```bash
# One-time send
zfsh backup send default backup@offsite:tank/backups

# Incremental after first full
zfsh backup send default backup@offsite:tank/backups -i
```

### Scheduled Remote Backup

```bash
zfsh cron add --type backup --pool default --daily \
    --remote backup@offsite:tank/backups \
    --compress zstd
```

### Bandwidth Limiting

For slow connections:

```bash
zfsh backup send default remote:tank/backup --bandwidth 10M
```

---

## Compression Recommendations

| Scenario | Compression | Reason |
|----------|-------------|--------|
| Local backup, fast disk | zstd | Best ratio/speed |
| Remote, slow network | zstd | Reduces transfer time |
| Local, limited CPU | lz4 | Minimal CPU overhead |
| Maximum compatibility | gzip | Universal support |
| Speed priority | none | No overhead |

### Compression Comparison

```bash
# Test compression ratio for your data
zfsh backup create default -c none -o /tmp/
zfsh backup create default -c zstd -o /tmp/
zfsh backup create default -c gzip -o /tmp/

ls -lh /tmp/default_*.zfs*
```

---

## Backup Verification

### Regular Verification

Schedule monthly verification:

```bash
# Verify all backups
for file in /root/backups/*.zfs*; do
    zfsh backup verify "$file"
done
```

### Test Restore

Periodically test full restore:

```bash
# Restore to temporary dataset
zfsh backup restore /root/backups/latest.zfs.zst default/test-restore

# Verify data
ls -la /default/test-restore/

# Clean up
zfs destroy default/test-restore
```

---

## Retention Management

### Local Backup Retention

```bash
# Keep last 10 backups
zfsh backup cleanup --keep-last 10 -y

# Or delete older than 30 days
zfsh backup cleanup --older-than 30d -y
```

### Automated Cleanup

Add to cron:

```bash
# Weekly cleanup
echo "0 4 * * 0 /opt/zfsh/zfs-backup.sh cleanup --keep-last 10 -y -q" | crontab -
```

### Storage Monitoring

```bash
# Check backup directory size
du -sh /root/backups/

# List backups with sizes
zfsh backup list --sort size
```

---

## Recovery Scenarios

### Scenario 1: Accidental Deletion

**Solution**: Rollback to snapshot

```bash
# Find snapshot before deletion
zfsh snapshot list --pool default

# Rollback
zfsh snapshot rollback default@backup_20260126 -y
```

### Scenario 2: Container Corruption

**Solution**: Restore specific container

```bash
# Stop container
incus stop web-server

# Restore from snapshot
zfsh snapshot rollback default/containers/web-server@backup_20260126 -f -y

# Start container
incus start web-server
```

### Scenario 3: Pool Failure

**Solution**: Restore from backup

```bash
# Create new pool
zfsh pool create default-new -s 100G -c zstd -y

# Restore from backup
zfsh backup restore /root/backups/default_20260126.zfs.zst default-new

# Verify data
zfsh pool info default-new -a
```

### Scenario 4: Server Failure

**Solution**: Restore on new server

```bash
# On new server: Install ZFS and ZFSh
apt install zfsutils-linux
git clone https://github.com/temasm/zfsh.git /opt/zfsh

# Create pool
zfsh pool create default -s 100G -c zstd -y

# Copy backup from offsite
scp backup@offsite:/tank/backups/default_20260126.zfs.zst /tmp/

# Restore
zfsh backup restore /tmp/default_20260126.zfs.zst default

# Initialize Incus
zfsh incus init -p default -y
```

---

## Complete Production Setup

```bash
#!/bin/bash
# Production backup setup script

POOL="default"
REMOTE="backup@offsite:tank/backups"

# Hourly snapshots
zfsh cron add --type snapshot --pool $POOL --hourly

# Daily snapshot cleanup (GFS retention)
zfsh cron add --type cleanup --pool $POOL --daily \
    --keep-daily 7 --keep-weekly 4 --keep-monthly 12

# Daily local backup
zfsh cron add --type backup --pool $POOL --daily \
    --compress zstd --time 02:00

# Daily remote backup
zfsh cron add --type backup --pool $POOL --daily \
    --remote $REMOTE --compress zstd --time 03:00

# Weekly local backup cleanup
echo "0 4 * * 0 /opt/zfsh/zfs-backup.sh cleanup --keep-last 14 -y -q" >> /var/spool/cron/crontabs/root

# Monthly scrub
zfsh cron add --type scrub --pool $POOL --monthly

echo "Backup system configured. Verify with: zfsh cron list"
```

---

## Best Practices Checklist

- [ ] Snapshots enabled (at least daily)
- [ ] Local backups configured
- [ ] Offsite/remote backups configured
- [ ] Retention policies set
- [ ] Backup verification scheduled
- [ ] Recovery procedures documented
- [ ] Recovery tested (at least annually)
- [ ] Monitoring alerts configured
