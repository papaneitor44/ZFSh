---
title: Retention Policies
description: Understanding and implementing snapshot retention with GFS
---

# Retention Policies

This guide explains snapshot retention strategies, with focus on the GFS (Grandfather-Father-Son) rotation scheme used by ZFSh.

## Why Retention Matters

Without retention policies:
- Snapshots accumulate indefinitely
- Storage fills up over time
- Performance can degrade with many snapshots
- Manual cleanup is error-prone

With retention policies:
- Automatic cleanup of old snapshots
- Predictable storage usage
- Balance between history depth and space

---

## GFS Retention Explained

GFS (Grandfather-Father-Son) is a rotation scheme that keeps snapshots at different granularities:

| Generation | Role | Retention | Typical Count |
|------------|------|-----------|---------------|
| **Son** | Daily snapshots | Recent history | 7 days |
| **Father** | Weekly snapshots | Medium-term | 4 weeks |
| **Grandfather** | Monthly snapshots | Long-term archive | 3-12 months |

### How It Works

1. **Daily (Son)**: Keep one snapshot per day for recent days
2. **Weekly (Father)**: Keep one snapshot per week (oldest of that week)
3. **Monthly (Grandfather)**: Keep one snapshot per month (oldest of that month)

### Example: `--keep-daily 7 --keep-weekly 4 --keep-monthly 3`

After running for several months:

```
Kept Snapshots:
├── Daily (last 7 days)
│   ├── backup_20260127  (today)
│   ├── backup_20260126  (yesterday)
│   ├── backup_20260125
│   ├── backup_20260124
│   ├── backup_20260123
│   ├── backup_20260122
│   └── backup_20260121
├── Weekly (last 4 weeks)
│   ├── backup_20260119  (week 3)
│   ├── backup_20260112  (week 2)
│   ├── backup_20260105  (week 1)
│   └── backup_20241229  (week 0)
└── Monthly (last 3 months)
    ├── backup_20241201  (December)
    ├── backup_20241101  (November)
    └── backup_20241001  (October)
```

Total: ~14 snapshots covering 4+ months

---

## Choosing Retention Periods

### Factors to Consider

1. **Recovery Point Objective (RPO)**: How much data loss is acceptable?
2. **Recovery scenarios**: What situations do you need to recover from?
3. **Storage capacity**: How much space can you dedicate to snapshots?
4. **Change rate**: How much data changes daily?

### Common Configurations

#### Minimal (Personal/Dev)

```bash
zfsh cron add --type cleanup --pool default --daily \
    --keep-last 5
```

Keeps only the last 5 snapshots. Simple but limited history.

#### Standard (Small Business)

```bash
zfsh cron add --type cleanup --pool default --daily \
    --keep-daily 7 \
    --keep-weekly 4
```

- 7 days of daily recovery points
- 4 weeks of weekly recovery points
- ~11 snapshots

#### Recommended (Production)

```bash
zfsh cron add --type cleanup --pool default --daily \
    --keep-daily 7 \
    --keep-weekly 4 \
    --keep-monthly 3
```

- Full week of daily recovery
- Month of weekly recovery
- Quarter of monthly recovery
- ~14 snapshots

#### Extended (Compliance/Archive)

```bash
zfsh cron add --type cleanup --pool default --daily \
    --keep-daily 14 \
    --keep-weekly 8 \
    --keep-monthly 12
```

- Two weeks of daily recovery
- Two months of weekly recovery
- Full year of monthly recovery
- ~34 snapshots

---

## Implementing Retention

### Step 1: Create Snapshots

First, ensure snapshots are being created:

```bash
# Daily snapshots
zfsh cron add --type snapshot --pool default --daily
```

### Step 2: Add Cleanup Task

Add cleanup with your chosen retention policy:

```bash
zfsh cron add --type cleanup --pool default --daily \
    --keep-daily 7 \
    --keep-weekly 4 \
    --keep-monthly 3
```

### Step 3: Preview Before Applying

Use `--dry-run` to see what would be deleted:

```bash
zfsh snapshot cleanup default \
    --keep-daily 7 \
    --keep-weekly 4 \
    --keep-monthly 3 \
    --dry-run
```

Output:
```
======================================
  Cleanup Plan
======================================

Retention policy:
  Keep daily: 7
  Keep weekly: 4
  Keep monthly: 3

Snapshots to delete (8):
  default@backup_20241115_020000 (age: 73 days)
  default@backup_20241120_020000 (age: 68 days)
  default@backup_20241125_020000 (age: 63 days)
  ...

[INFO]  Dry run - no changes made
```

### Step 4: Apply Manually (First Time)

```bash
zfsh snapshot cleanup default \
    --keep-daily 7 \
    --keep-weekly 4 \
    --keep-monthly 3 \
    -y
```

---

## Multiple Snapshot Types

If you have different snapshot types (hourly, daily, backup):

### Using Prefixes

```bash
# Hourly snapshots with own retention
zfsh cron add --type snapshot --pool default --hourly
# (prefix: backup by default)

# Cleanup only hourly snapshots
zfsh snapshot cleanup default --prefix hourly --keep-last 24 -y
```

### Separate Schedules

```bash
# Hourly: keep 24
zfsh cron add --type cleanup --pool default --hourly \
    --keep-last 24

# Daily: GFS policy
zfsh cron add --type cleanup --pool default --daily \
    --keep-daily 7 --keep-weekly 4 --keep-monthly 3
```

---

## Storage Estimation

### Snapshot Space Usage

ZFS snapshots use copy-on-write:
- Initial snapshot: ~0 bytes (just metadata)
- Over time: only changed blocks consume space

### Estimating Requirements

```bash
# Check current snapshot usage
zfs list -t snapshot -o name,used,refer | grep default
```

Example output:
```
NAME                              USED    REFER
default@backup_20260125_020000    64K     96K
default@backup_20260126_020000    128K    98K
default@backup_20260127_020000    0B      100K
```

### Rule of Thumb

- **Low change rate** (web servers): 1-5% of dataset per day
- **Medium change rate** (databases): 5-15% of dataset per day
- **High change rate** (active development): 15-30%+ per day

For a 100GB pool with medium change rate:
- Daily snapshots: ~10GB/day
- 7 daily + 4 weekly + 3 monthly (~14 snapshots): ~50-100GB total

---

## Troubleshooting

### "No snapshots to delete"

The retention policy is keeping all snapshots. Either:
- Not enough snapshots yet
- Retention is too generous

Check current snapshots:
```bash
zfsh snapshot list --pool default
```

### Snapshots Taking Too Much Space

1. Check which snapshots use space:
   ```bash
   zfs list -t snapshot -o name,used -s used | tail -20
   ```

2. Reduce retention:
   ```bash
   zfsh snapshot cleanup default --keep-daily 3 --keep-weekly 2 -y
   ```

3. Delete specific large snapshots:
   ```bash
   zfsh snapshot delete default@old-snapshot -y
   ```

### Pool Filling Up

1. Check snapshot usage:
   ```bash
   zfs list -t snapshot -o name,used | grep default | awk '{sum+=$2} END {print sum}'
   ```

2. Run aggressive cleanup:
   ```bash
   zfsh snapshot cleanup default --keep-last 5 -y
   ```

3. Expand pool if needed:
   ```bash
   zfsh pool expand default -a 20G -y
   ```

---

## Best Practices

1. **Start conservative**: Begin with generous retention, reduce if space is tight
2. **Monitor regularly**: Check snapshot space usage weekly
3. **Use dry-run**: Always preview cleanup before applying
4. **Test recovery**: Ensure you can actually restore from kept snapshots
5. **Document policy**: Record why you chose specific retention periods
6. **Review periodically**: Adjust retention as needs change
