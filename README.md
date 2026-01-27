# ZFSh

**ZFS Shell Helpers** — a collection of bash scripts for simplified ZFS pool, snapshot, and backup management with Incus integration.

## Features

- **Pool Management** — Create, monitor, expand file-backed ZFS pools
- **Snapshot Management** — Create, list, delete, rollback with GFS retention policies
- **Backup & Restore** — Local and remote backups with compression (zstd, gzip, lz4)
- **Health Monitoring** — Comprehensive pool health checks with recommendations
- **Incus Integration** — One-command Incus initialization with ZFS backend
- **Scheduled Tasks** — Easy cron job management for automated operations
- **Interactive Mode** — User-friendly menu-driven interface

## Quick Start

```bash
# Clone the repository
git clone https://github.com/temasm/zfsh.git
cd zfsh

# Make scripts executable
chmod +x zfsh *.sh

# Run interactive menu
./zfsh
```

## Requirements

- Linux with ZFS installed (`zfsutils-linux` or equivalent)
- Bash 4.0+
- Root privileges for most operations
- Optional: `pv` for progress bars, `zstd`/`gzip`/`lz4` for compression

## Installation

### Option 1: Clone Repository

```bash
git clone https://github.com/temasm/zfsh.git /opt/zfsh
ln -s /opt/zfsh/zfsh /usr/local/bin/zfsh
```

### Option 2: Download Scripts

```bash
curl -L https://github.com/temasm/zfsh/archive/main.tar.gz | tar xz
cd zfsh-main
chmod +x zfsh *.sh
```

## Usage

### Interactive Mode

Simply run `zfsh` without arguments to access the interactive menu:

```bash
./zfsh
```

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

### Command Line Interface

```bash
# Pool operations
zfsh pool create mypool -s 50G -c zstd -d on
zfsh pool info mypool
zfsh pool health mypool
zfsh pool expand mypool -a 20G

# Snapshot operations
zfsh snapshot create mypool/data
zfsh snapshot list --pool mypool
zfsh snapshot cleanup mypool --keep-daily 7 --keep-weekly 4

# Backup operations
zfsh backup create mypool -c zstd
zfsh backup restore backup.zfs.zst mypool/restored
zfsh backup send mypool user@remote:tank/backup

# Incus integration
zfsh incus init -p mypool

# Scheduled tasks
zfsh cron add --type snapshot --pool mypool --daily
zfsh cron list
```

## Commands Overview

| Command | Description |
|---------|-------------|
| `zfsh pool create` | Create new ZFS pool on sparse file |
| `zfsh pool info` | Display pool information |
| `zfsh pool expand` | Expand file-backed pool |
| `zfsh pool health` | Check pool health with recommendations |
| `zfsh snapshot create` | Create snapshot |
| `zfsh snapshot list` | List snapshots |
| `zfsh snapshot cleanup` | Apply retention policy |
| `zfsh snapshot rollback` | Rollback to snapshot |
| `zfsh backup create` | Create backup file |
| `zfsh backup restore` | Restore from backup |
| `zfsh backup send` | Send to remote server |
| `zfsh incus init` | Initialize Incus with ZFS |
| `zfsh cron add` | Add scheduled task |
| `zfsh cron list` | List scheduled tasks |
| `zfsh cron remove` | Remove scheduled task |

## Example Workflow

```bash
# 1. Create a 50GB ZFS pool with compression and dedup
zfsh pool create default -s 50G -c zstd -d on -y

# 2. Initialize Incus with the pool
zfsh incus init -p default -y

# 3. Set up daily snapshots with retention
zfsh cron add --type snapshot --pool default --daily
zfsh cron add --type cleanup --pool default --daily \
    --keep-daily 7 --keep-weekly 4 --keep-monthly 3

# 4. Create containers
incus launch images:debian/12 web-server
incus launch images:ubuntu/24.04 app-server

# 5. Manual backup before maintenance
zfsh backup create default -c zstd

# 6. Check pool health
zfsh pool health default
```

## Documentation

Full documentation available in the [docs](./docs/) directory:

- [Getting Started](./docs/getting-started.md)
- [Commands Reference](./docs/commands/)
- [Guides](./docs/guides/)
- [CLI Reference](./docs/reference/cli-reference.md)

## Project Structure

```
zfsh/
├── zfsh                    # Main entry point
├── common.sh               # Shared library
├── zfs-pool-create.sh      # Pool creation
├── zfs-pool-info.sh        # Pool information
├── zfs-pool-expand.sh      # Pool expansion
├── zfs-pool-health.sh      # Health checks
├── zfs-snapshot.sh         # Snapshot management
├── zfs-backup.sh           # Backup operations
├── zfs-cron-setup.sh       # Cron management
├── zfs-incus-init.sh       # Incus initialization
└── docs/                   # Documentation
```

## Output Formats

All commands support JSON output for scripting:

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
    "total": 53687091200,
    "total_human": "50G",
    "used": 1073741824,
    "free": 52613349376,
    "capacity_percent": 2,
    "dedup_ratio": 1.00
  }
}
```

## Contributing

Contributions are welcome! Please read the [Contributing Guide](./CONTRIBUTING.md) before submitting a Pull Request.

## License

This project is licensed under the MIT License — see the [LICENSE](./LICENSE) file for details.

## Acknowledgments

- Built for managing ZFS pools on VPS/dedicated servers
- Designed for Incus container environments
- Inspired by the need for simple, scriptable ZFS management
