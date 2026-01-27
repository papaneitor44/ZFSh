---
title: Reference
description: Technical reference documentation for ZFSh
---

# Reference

Technical reference documentation for ZFSh, including complete CLI specifications and exit codes.

## Contents

### [CLI Reference](./cli-reference.md)

Complete command-line reference with all options and arguments:

- All commands and subcommands
- Global options
- Size and age format specifications
- Environment variables
- Configuration files

### [Exit Codes](./exit-codes.md)

Exit codes returned by ZFSh scripts:

- General exit codes (0-5)
- Command-specific codes
- Using exit codes in scripts
- Monitoring integration examples

## Quick Reference

### Global Options

All commands support these options:

| Option | Short | Description |
|--------|-------|-------------|
| `--help` | `-h` | Show help message |
| `--json` | `-j` | Output in JSON format |
| `--quiet` | `-q` | Minimal output |
| `--log FILE` | `-l` | Log output to file |

### Common Exit Codes

| Code | Meaning |
|------|---------|
| 0 | Success |
| 1 | General error |
| 2 | Usage/argument error |
| 3 | Resource not found |
| 4 | Permission denied |
| 5 | Missing dependency |

### Size Formats

```
50G   → 50 gigabytes
100M  → 100 megabytes
1T    → 1 terabyte
```

### Age Formats

```
7d    → 7 days
2w    → 2 weeks
3m    → 3 months
24h   → 24 hours
```

## See Also

- [Commands Overview](../commands/) — All available commands
- [Getting Started](../getting-started.md) — Installation and quick start
