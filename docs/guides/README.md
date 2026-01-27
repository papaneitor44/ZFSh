---
title: Guides
description: Step-by-step guides for common ZFSh workflows
---

# Guides

Step-by-step guides for common workflows and best practices with ZFSh.

## Available Guides

### [Basic Workflow](./basic-workflow.md)

Complete walkthrough from pool creation to running containers:

- Creating and configuring a ZFS pool
- Initializing Incus
- Deploying containers
- Setting up automated snapshots

### [Backup Strategy](./backup-strategy.md)

Design a reliable backup system:

- Local vs. remote backups
- Full and incremental backup strategies
- Scheduling automated backups
- Testing and verifying backups
- Disaster recovery planning

### [Retention Policies](./retention-policies.md)

Understanding and implementing snapshot retention:

- GFS (Grandfather-Father-Son) explained
- Choosing retention periods
- Combining retention with cleanup
- Storage considerations

## Quick Reference

### Recommended Production Setup

```bash
# 1. Create pool with compression
zfsh pool create default -s 100G -c zstd -y

# 2. Initialize Incus
zfsh incus init -p default -y

# 3. Set up automation
zfsh cron add --type snapshot --pool default --daily
zfsh cron add --type cleanup --pool default --daily \
    --keep-daily 7 --keep-weekly 4 --keep-monthly 3
zfsh cron add --type backup --pool default --weekly
zfsh cron add --type scrub --pool default --monthly
```

### Common Tasks

| Task | Command |
|------|---------|
| Check pool status | `zfsh pool health default` |
| Create manual snapshot | `zfsh snapshot create default` |
| Restore from snapshot | `zfsh snapshot rollback default@snapshot-name` |
| Create backup | `zfsh backup create default -c zstd` |
| List backups | `zfsh backup list` |
| View scheduled tasks | `zfsh cron list` |
