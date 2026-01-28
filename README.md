# BashUpdate

BashUpdate is a comprehensive Bash script for performing routine system updates and maintenance on Debian-based systems. It updates system packages, snap packages, performs cleanup operations, and handles Docker maintenance.

## Features

- **System Updates & Upgrades**:
  - Updates package lists using `apt update`
  - Performs a full system upgrade with `apt full-upgrade`
  - Automatically installs required dependencies (e.g., `curl`)

- **Snap Package Updates**:
  - Updates all installed snap packages using `snap refresh`

- **System Cleanup**:
  - Removes unused packages with `apt autoremove --purge`
  - Cleans APT cache with `apt clean` and `apt autoclean`
  - Removes old kernel packages

- **Log Maintenance**:
  - Vacuums systemd journal to retain logs for a specified period (default: 7 days)
  - Trims update script log file if it exceeds 20,000 lines

- **Docker Maintenance**:
  - If Docker is installed, the script will:
    - Download and cache `dockcheck.sh` in `/usr/local/lib/update-script/` (persists between runs)
    - Run dockcheck to update Docker containers (if enabled)
    - Prune unused Docker images, volumes, and networks
    - Perform deep cleanup of all unused Docker resources

- **Disk Space Check**:
  - Verifies that a minimum disk space threshold (1GB by default) is available before executing updates

- **Raspberry Pi Specific Tasks**:
  - Checks for Raspberry Pi hardware and, if detected, optionally runs `unifi-update.sh` script if available

## Configuration

The script can be configured via environment variables:

- `LOG_DIR`: Directory for log files (default: `/var/log/update-script`)
- `LOG_FILE`: Path to log file (default: `$LOG_DIR/update.log`)
- `REQUIRED_DISK_KB`: Minimum disk space required in KB (default: `1048576` = 1GB)
- `JOURNAL_VACUUM_TIME`: Systemd journal retention period (default: `7d`)
- `RUN_DOCKCHECK`: Enable/disable dockcheck (default: `1` = enabled)
- `DOCKCHECK_REF`: Branch/tag for dockcheck script (default: `main`)
- `DOCKCHECK_OPTS`: Options to pass to dockcheck (default: `-apfs`)

## Requirements

- **Operating System**: Debian-based systems (including Raspberry Pi OS)
- **Bash**: Version 4.x or higher
- **Privileges**: Must be run as root (or via `sudo`)
- **Required Commands**: `apt-get`, `dpkg`, `grep`, `awk`, `df`, `find` (all checked automatically)
- **Optional Dependencies**:
  - `docker` (if you want to perform Docker maintenance)
  - `snap` (if you want to update snap packages)
  - `curl` (automatically installed if needed for dockcheck)

## Usage

```bash
sudo ./update.sh
```

The script will:
1. Check for root privileges and required dependencies
2. Verify sufficient disk space
3. Update package lists
4. Install required dependencies
5. Upgrade system packages
6. Update snap packages
7. Clean up unused packages and cache
8. Remove old kernel packages
9. Clean up system logs
10. Perform Docker maintenance (if Docker is installed)
11. Optionally run unifi-update.sh on Raspberry Pi systems

All output is logged to `/var/log/update-script/update.log` by default.

## Output Format

The script provides concise output with full sentences, showing progress for each section:
- Section headers indicate what operation is being performed
- Warnings and errors are clearly marked
- Most operations run silently unless there are issues
- Docker dockcheck output is shown when enabled

## Notes

- The script uses `set -euo pipefail` for strict error handling
- All apt operations use non-interactive mode
- Docker dockcheck script is cached in `/usr/local/lib/update-script/` to avoid re-downloading
- If a system reboot is required after updates, you'll be prompted at the end
