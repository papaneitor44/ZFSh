# Contributing to ZFSh

Thank you for your interest in contributing to ZFSh! This document provides guidelines and information for contributors.

## Code of Conduct

Please be respectful and constructive in all interactions. We welcome contributors of all experience levels.

## How to Contribute

### Reporting Bugs

Before submitting a bug report:

1. Check the [existing issues](https://github.com/temasm/zfsh/issues) to avoid duplicates
2. Collect relevant information:
   - ZFSh version (`zfsh --version`)
   - ZFS version (`zfs --version`)
   - Linux distribution and version
   - Full error message and command output

Use the [bug report template](.github/ISSUE_TEMPLATE/bug_report.md) when creating an issue.

### Suggesting Features

Feature requests are welcome! Please use the [feature request template](.github/ISSUE_TEMPLATE/feature_request.md) and include:

- Clear description of the proposed feature
- Use case and motivation
- Possible implementation approach (optional)

### Submitting Changes

1. **Fork the repository** and create your branch from `main`
2. **Make your changes** following the coding standards below
3. **Test your changes** thoroughly
4. **Submit a Pull Request** using the PR template

## Development Setup

```bash
# Clone your fork
git clone https://github.com/YOUR_USERNAME/zfsh.git
cd zfsh

# Make scripts executable
chmod +x zfsh *.sh

# Test in a safe environment (VM or test server with ZFS)
```

## Coding Standards

### Bash Style

- Use `#!/bin/bash` shebang
- Enable strict mode: `set -euo pipefail`
- Use lowercase for local variables: `local my_var="value"`
- Use UPPERCASE for constants and exports: `BACKUP_DIR="/root/backups"`
- Quote all variables: `"$variable"` not `$variable`
- Use `[[ ]]` for conditionals, not `[ ]`

### Script Structure

Follow the existing pattern:

```bash
#!/bin/bash
# script-name.sh - Brief description
#
# Usage: script-name.sh [OPTIONS]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

# =============================================================================
# DEFAULTS
# =============================================================================
VARIABLE="default_value"

# =============================================================================
# FUNCTIONS
# =============================================================================
show_help() {
    cat << 'EOF'
Description and usage...
EOF
}

# =============================================================================
# MAIN
# =============================================================================
main() {
    parse_args "$@"
    # Implementation
}

main "$@"
```

### Comments

- Add header comments to each script
- Document complex logic
- Use `# =============================================================================` for section separators

### Error Handling

- Use `die "message"` for fatal errors (from common.sh)
- Validate user input before operations
- Provide clear error messages

### Output

- Use helper functions from `common.sh`:
  - `info "message"` — informational
  - `success "message"` — success (green)
  - `warn "message"` — warning (yellow)
  - `error "message"` — error (red)
- Support `--json` flag for scriptable output
- Support `--quiet` flag for minimal output

## Testing

### Manual Testing

Test your changes on a system with ZFS installed. For destructive operations, use:

- A test VM
- A separate test pool
- The `--dry-run` flag where available

### Test Checklist

- [ ] Script runs without errors
- [ ] Help text is correct (`--help`)
- [ ] JSON output is valid (`--json`)
- [ ] Error handling works correctly
- [ ] Works with and without color output

## Pull Request Process

1. Update documentation if needed
2. Add yourself to contributors (optional)
3. Ensure all tests pass
4. Request review from maintainers

### PR Title Format

Use clear, descriptive titles:

- `feat: Add support for LZ4 compression`
- `fix: Handle spaces in dataset names`
- `docs: Update backup examples`
- `refactor: Simplify retention policy logic`

## Questions?

Feel free to open an issue with the "question" label if you need help or clarification.

---

Thank you for contributing to ZFSh!
