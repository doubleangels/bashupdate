# BashUpdate

BashUpdate is a simple Bash script for performing routine system updates and maintenance on Raspberry Pi and Debian-based systems. It not only updates system packages but also handles Docker maintenance and performs Raspberry Pi–specific tasks such as firmware updates and optional Unifi controller updates.

## Features

- **System Updates & Upgrades**:  
  - Updates package lists using `apt update`
  - Performs a full system upgrade with `apt full-upgrade`
  - Removes unnecessary packages with `apt autoremove`

- **Disk Space Check**:  
  - Verifies that a minimum disk space threshold (~512MB by default) is available before executing updates.

- **Raspberry Pi Specific Tasks**:  
  - Checks for Raspberry Pi hardware and, if detected, prompts for a firmware upgrade using `rpi-update`
  - Optionally runs a Unifi update script (`unifi-update.sh`) if available

- **Docker Maintenance**:  
  - If Docker is installed, the script will run Docker-specific maintenance, including:
    - Downloading and executing `dockcheck.sh` if not present locally
    - Pruning unused Docker containers, networks, images, and volumes

- **Verbose Mode**:  
  - Use the `-v` option to enable detailed output (using shell's debug mode).

## Requirements

- **Operating System**: Debian-based systems or Raspberry Pi OS  
- **Bash**: Tested on version 4.x or higher  
- **Privileges**: Must be run as root (or via `sudo`)  
- **Optional Dependencies**:  
  - `rpi-update` for firmware updates (the script will install it if missing)  
  - `docker` (if you want to perform Docker maintenance)  
  - `curl` for downloading external scripts if needed
