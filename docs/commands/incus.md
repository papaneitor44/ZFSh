---
title: Incus Integration
description: Initialize Incus container environment with ZFS backend
---

# Incus Integration

ZFSh provides one-command Incus initialization with ZFS backend, creating storage pools, networks, and default profiles automatically.

## Commands

- [`zfsh incus init`](#incus-init) — Initialize Incus with ZFS pool

---

## incus init

Initialize Incus to use an existing ZFS pool as its storage backend.

### Usage

```bash
zfsh incus init [options]
```

### Options

| Option | Description | Default |
|--------|-------------|---------|
| `-p, --pool NAME` | ZFS pool name | default |
| `-s, --storage NAME` | Incus storage pool name | Same as ZFS pool |
| `-n, --network NAME` | Bridge network name | incusbr0 |
| `--network-ipv4 CIDR` | IPv4 subnet | Auto |
| `--no-network` | Skip network creation | - |
| `-y, --yes` | Skip confirmation | - |

### What Gets Created

1. **Storage Pool** — Incus storage pool using the ZFS pool
2. **Bridge Network** — NAT-enabled bridge for container networking
3. **Default Profile** — Configured with root disk and network interface

### Examples

<details>
<summary>Initialize with defaults</summary>

```bash
zfsh incus init -p default -y
```

```
======================================
  Incus Initialization with ZFS
======================================

Summary:
  ZFS pool:      default
  Storage name:  default
  Network:       incusbr0 (create new)

[INFO]  Applying Incus configuration...
Preseed configuration:
---
storage_pools:
- name: default
  driver: zfs
  config:
    source: default
networks:
- name: incusbr0
  type: bridge
profiles:
- name: default
  devices:
    root:
      path: /
      pool: default
      type: disk
    eth0:
      name: eth0
      network: incusbr0
      type: nic
---

[OK]    Incus initialized successfully
[INFO]  Verifying setup...
[OK]    Storage pool 'default' created
[OK]    Network 'incusbr0' available
[OK]    Default profile configured

Setup complete! You can now create containers:

  incus launch images:debian/12 my-container
  incus launch images:ubuntu/24.04 my-ubuntu

Useful commands:
  incus list                    # List containers
  incus storage info default    # Storage info
  incus network list            # List networks
```

</details>

<details>
<summary>Custom storage and network names</summary>

```bash
zfsh incus init -p mypool -s storage -n br0 -y
```

```
Summary:
  ZFS pool:      mypool
  Storage name:  storage
  Network:       br0 (create new)

[INFO]  Applying Incus configuration...
[OK]    Incus initialized successfully
```

</details>

<details>
<summary>With specific IPv4 subnet</summary>

```bash
zfsh incus init -p default --network-ipv4 10.100.0.1/24 -y
```

This creates a network with:
- Gateway: 10.100.0.1
- DHCP range: 10.100.0.2 - 10.100.0.254
- NAT enabled for internet access

</details>

<details>
<summary>Skip network creation</summary>

```bash
zfsh incus init -p default --no-network -y
```

Use this if you already have a network configured or want to set it up manually.

</details>

<details>
<summary>JSON output</summary>

```bash
zfsh incus init -p default -y --json
```

```json
{
  "success": true,
  "storage": {
    "name": "default",
    "driver": "zfs",
    "source": "default"
  },
  "network": {
    "name": "incusbr0",
    "ipv4": "10.10.10.1/24"
  }
}
```

</details>

---

## After Initialization

### Creating Containers

```bash
# Debian 12
incus launch images:debian/12 web-server

# Ubuntu 24.04
incus launch images:ubuntu/24.04 app-server

# Alpine (minimal)
incus launch images:alpine/3.19 alpine-vm
```

### Managing Containers

```bash
# List containers
incus list

# Start/stop
incus start web-server
incus stop web-server

# Shell access
incus exec web-server -- bash

# View logs
incus console web-server --show-log
```

### Storage Information

```bash
# Storage pool info
incus storage info default

# List volumes
incus storage volume list default
```

### Network Information

```bash
# List networks
incus network list

# Network details
incus network show incusbr0
```

---

## ZFS Benefits for Containers

Using ZFS as the Incus storage backend provides:

### Instant Snapshots

```bash
# Snapshot a container
incus snapshot web-server backup

# Restore from snapshot
incus restore web-server backup
```

### Efficient Cloning

```bash
# Clone a container (uses ZFS clone, instant)
incus copy web-server web-server-clone
```

### Container-Level Backup

```bash
# Export container (includes ZFS data)
incus export web-server web-server-backup.tar.gz

# Import on another server
incus import web-server-backup.tar.gz
```

### Dataset-Level Backup with ZFSh

```bash
# Backup all container data
zfsh backup create default/containers -c zstd

# Or backup specific container
zfsh snapshot create default/containers/web-server
```

---

## Troubleshooting

### "Incus not installed"

Install Incus first:

```bash
# Debian/Ubuntu (from Zabbly repository)
curl -fsSL https://pkgs.zabbly.com/get/incus-stable | sh
```

### "Storage pool already exists"

If you've already initialized Incus:

```bash
# Check existing storage
incus storage list

# Remove if needed (WARNING: destroys data)
incus storage delete old-pool
```

### "Network already exists"

Use the existing network:

```bash
zfsh incus init -p default --no-network -y
```

Or specify a different network name:

```bash
zfsh incus init -p default -n br1 -y
```

### Container can't access internet

Check NAT is enabled:

```bash
incus network show incusbr0 | grep nat
# Should show: ipv4.nat: "true"

# Enable if missing
incus network set incusbr0 ipv4.nat=true
```

---

## Best Practices

1. **Use dedicated pool** — Separate ZFS pool for containers
2. **Enable compression** — zstd on ZFS pool saves space
3. **Regular snapshots** — Use ZFSh cron for automated snapshots
4. **Monitor usage** — Check pool capacity with `zfsh pool health`
5. **Backup strategy** — Combine ZFS snapshots with container exports
