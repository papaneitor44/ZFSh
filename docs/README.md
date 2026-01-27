---
title: ZFSh Documentation
description: ZFS Shell Helpers - simplified ZFS management for Linux
---

# ZFSh Documentation

Welcome to the ZFSh documentation. ZFSh (ZFS Shell Helpers) is a collection of bash scripts designed to simplify ZFS pool, snapshot, and backup management on Linux systems.

## Overview

ZFSh provides an intuitive interface for common ZFS operations:

- **Pool Management** — Create and manage file-backed ZFS pools
- **Snapshot Management** — Create, list, delete snapshots with retention policies
- **Backup & Restore** — Full and incremental backups with compression
- **Health Monitoring** — Comprehensive pool health checks
- **Incus Integration** — One-command container environment setup
- **Scheduled Tasks** — Automated snapshots and backups via cron

## Documentation Structure

### Getting Started

- [Installation & Quick Start](./getting-started.md) — Install ZFSh and create your first pool

### Commands

Detailed reference for all ZFSh commands:

- [Commands Overview](./commands/)
- [Pool Management](./commands/pool.md) — `zfsh pool create|info|expand|health`
- [Snapshot Management](./commands/snapshot.md) — `zfsh snapshot create|list|delete|cleanup`
- [Backup & Restore](./commands/backup.md) — `zfsh backup create|restore|send`
- [Incus Integration](./commands/incus.md) — `zfsh incus init`
- [Scheduled Tasks](./commands/cron.md) — `zfsh cron add|list|remove`

### Guides

Step-by-step guides for common workflows:

- [Guides Overview](./guides/)
- [Basic Workflow](./guides/basic-workflow.md) — From pool creation to container deployment
- [Backup Strategy](./guides/backup-strategy.md) — Designing a reliable backup system
- [Retention Policies](./guides/retention-policies.md) — Understanding GFS retention

### Reference

- [Reference Overview](./reference/) — Technical reference documentation
- [CLI Reference](./reference/cli-reference.md) — Complete command-line reference
- [Exit Codes](./reference/exit-codes.md) — Script exit codes and their meanings

## Quick Links

| Task | Command |
|------|---------|
| Create 50GB pool | `zfsh pool create mypool -s 50G` |
| Check pool health | `zfsh pool health mypool` |
| Create snapshot | `zfsh snapshot create mypool` |
| Backup to file | `zfsh backup create mypool` |
| Setup Incus | `zfsh incus init -p mypool` |
| Schedule snapshots | `zfsh cron add --type snapshot --pool mypool --daily` |

## Features at a Glance

### Interactive Mode

Run `zfsh` without arguments for a menu-driven interface:

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
```

### JSON Output

All commands support `--json` for scripting and automation:

```bash
zfsh pool info mypool --json | jq '.storage.free_human'
```

### Quiet Mode

Use `--quiet` for minimal output in scripts:

```bash
zfsh snapshot create mypool --quiet && echo "Snapshot created"
```

## Requirements

- Linux with ZFS support
- Bash 4.0+
- Root privileges (for ZFS operations)
- Optional: `pv` (progress), `zstd`/`gzip`/`lz4` (compression)

## Getting Help

- Run `zfsh --help` for general help
- Run `zfsh <command> --help` for command-specific help
- Check the [CLI Reference](./reference/cli-reference.md) for detailed options
- [Open an issue](https://github.com/temasm/zfsh/issues) for bugs or feature requests
