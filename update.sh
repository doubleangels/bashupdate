#!/usr/bin/env bash
#
# A simple update & maintenance script for Raspberry Pi (or Debian-based systems).

# --------------------------------------------------
# Enable unofficial bash "strict mode":
# - e : Exit immediately if a command exits with a non-zero status
# - u : Treat unset variables as an error
# - o pipefail : Pipeline returns the exit status of the last command that had a non-zero exit code
# --------------------------------------------------
set -euo pipefail

# --------------------------------------------------
# Globals
# --------------------------------------------------
SCRIPT_NAME="$(basename "$0")"
HOSTNAME="$(hostname)"
UPDATES_SUMMARY=""

# --------------------------------------------------
# Functions
# --------------------------------------------------

function print_section() {
    echo -e "\n\e[1;33m${1}\e[0m"
}

function append_summary() {
    UPDATES_SUMMARY+="\n- ${1}"
}

# (4) Validate Dependencies
function check_dependencies() {
    # Add any commands you consider essential
    local required_commands=("apt" "grep" "df" "bash")

    for cmd in "${required_commands[@]}"; do
        if ! command -v "$cmd" &>/dev/null; then
            echo -e "\n\e[1;31mError: '$cmd' is not installed or not in PATH. Please install it and re-run.\e[0m"
            exit 1
        fi
    done
}

# (2) Disk Space Check
function check_disk_space() {
    # Adjust the required space as desired (in 1K-blocks or MB).
    # df --output=avail returns 1K-blocks by default, so 512000 for 512MB, etc.
    local required_kb=512000  # ~512MB
    local available_kb

    available_kb="$(df --output=avail / | tail -n1)"
    if (( available_kb < required_kb )); then
        echo -e "\n\e[1;31mInsufficient disk space available (less than ~512MB). Exiting.\e[0m"
        exit 1
    fi
}

# --------------------------------------------------
# Update system package lists
# --------------------------------------------------
function update_packages() {
    print_section "Updating package information..."
    if apt update; then
        append_summary "Package information updated."
    else
        append_summary "Package information update failed."
    fi
}

# --------------------------------------------------
# Perform a full upgrade
# --------------------------------------------------
function full_upgrade() {
    print_section "Performing a full upgrade of installed packages..."
    if apt full-upgrade -y; then
        append_summary "Full upgrade of installed packages performed."
    else
        append_summary "Full upgrade failed."
    fi
}

# --------------------------------------------------
# Remove unnecessary packages
# --------------------------------------------------
function autoremove_packages() {
    print_section "Removing unnecessary packages..."
    if apt autoremove -y; then
        append_summary "Unnecessary packages removed."
    else
        append_summary "Autoremove failed."
    fi
}

# --------------------------------------------------
# Upgrade Raspberry Pi firmware (rpi-update)
# --------------------------------------------------
function upgrade_firmware() {
    # Only run on Raspberry Pi systems
    if ! grep -q "Raspberry Pi" /proc/cpuinfo; then
        print_section "Not a Raspberry Pi system, skipping rpi-update firmware upgrade."
        append_summary "Raspberry Pi firmware upgrade skipped (not a Raspberry Pi)."
        return
    fi

    print_section "Upgrading firmware..."

    if ! command -v rpi-update &>/dev/null; then
        print_section "rpi-update is not installed, installing it..."
        apt update
        apt install -y rpi-update
        append_summary "rpi-update installed."
    fi

    read -rp "Do you want to run firmware update (rpi-update)? [y/N]: " run_rpi_update
    if [[ "${run_rpi_update}" =~ ^[Yy]$ ]]; then
        rpi-update
        append_summary "Firmware upgraded using rpi-update."
    else
        append_summary "Firmware upgrade skipped."
    fi
}

# --------------------------------------------------
# Handle fwupd firmware updates
# --------------------------------------------------
function fwupd_firmware_update() {
    print_section "Checking for fwupd firmware updates..."
    
    # Install fwupd if not present
    if ! command -v fwupdmgr &>/dev/null; then
        print_section "fwupd is not installed, installing it..."
        apt update
        apt install -y fwupd
        append_summary "fwupd installed."
    fi
    
    # Get devices
    print_section "Getting firmware devices..."
    fwupdmgr get-devices
    append_summary "Firmware devices listed."
    
    # Refresh metadata
    print_section "Refreshing firmware metadata..."
    fwupdmgr refresh --force
    append_summary "Firmware metadata refreshed."
    
    # Check for updates
    print_section "Checking for firmware updates..."
    local updates_available
    updates_available=$(fwupdmgr get-updates 2>&1 | grep -c "No updates available" || true)
    append_summary "Firmware updates checked."
    
    # Apply updates only if available
    if [[ "$updates_available" -eq 0 ]]; then
        print_section "Applying firmware updates..."
        fwupdmgr update
        append_summary "Firmware updates applied."
    else
        print_section "No firmware updates available, skipping update step."
        append_summary "No firmware updates available, skipped update step."
    fi
}

# --------------------------------------------------
# Handle Docker maintenance
# --------------------------------------------------
function docker_maintenance() {
    print_section "Checking for Docker maintenance..."
    
    if command -v docker &>/dev/null; then
        print_section "Docker found. Updating and running dockcheck.sh..."
        
        if command -v curl &>/dev/null; then
            # Always download the latest version of dockcheck.sh
            print_section "Downloading latest dockcheck.sh from GitHub..."
            curl -o dockcheck.sh \
                https://raw.githubusercontent.com/mag37/dockcheck/main/dockcheck.sh
            if [[ -f "dockcheck.sh" ]]; then
                chmod +x dockcheck.sh
                print_section "Running dockcheck.sh (updating stopped containers and restarting stacks)..."
                bash ./dockcheck.sh -apfs
                append_summary "Downloaded latest dockcheck.sh and ran Docker maintenance."
            else
                echo -e "\n\e[1;31mFailed to download dockcheck.sh. Skipping Docker maintenance.\e[0m"
            fi
        else
            echo -e "\n\e[1;31mcurl is not installed. Skipping Docker maintenance.\e[0m"
        fi

        # Automatically prune Docker resources
        print_section "Removing all unused Docker containers, networks, images, and volumes (forced prune)..."
        docker system prune -fa
        append_summary "Removed all unused Docker containers, networks, images, and volumes (force)."
    else
        print_section "Docker not found. Skipping Docker maintenance."
        append_summary "Docker maintenance skipped (Docker not installed)."
    fi
}

# --------------------------------------------------
# Clean up apt cache
# --------------------------------------------------
function cleanup_apt_cache() {
    print_section "Cleaning up apt cache..."
    if apt clean; then
        append_summary "APT cache cleaned."
    else
        append_summary "APT cache cleanup failed."
    fi
}

# --------------------------------------------------
# Remove log files older than 7 days
# --------------------------------------------------
function cleanup_old_logs() {
    print_section "Removing log files older than 7 days..."
    local log_dirs=("/var/log" "/var/log/journal")
    local removed_count=0
    
    for log_dir in "${log_dirs[@]}"; do
        if [[ -d "$log_dir" ]]; then
            local count
            count=$(find "$log_dir" -type f -name "*.log" -mtime +7 -delete -print 2>/dev/null | wc -l)
            removed_count=$((removed_count + count))
        fi
    done
    
    if [[ $removed_count -gt 0 ]]; then
        append_summary "Removed $removed_count log files older than 7 days."
    else
        append_summary "No log files older than 7 days found."
    fi
}

# --------------------------------------------------
# Remove old kernels except current one
# --------------------------------------------------
function cleanup_old_kernels() {
    print_section "Removing old kernels (keeping current one)..."
    
    # Get current kernel version
    local current_kernel
    current_kernel=$(uname -r)
    
    # Remove old kernel packages
    if apt autoremove --purge -y; then
        append_summary "Old kernel packages removed."
    else
        append_summary "Old kernel cleanup failed."
    fi
    
    # Clean up old kernel headers and modules
    local old_kernels
    old_kernels=$(dpkg -l | grep -E 'linux-image-[0-9]' | grep -v "$current_kernel" | awk '{print $2}')
    
    if [[ -n "$old_kernels" ]]; then
        for kernel in $old_kernels; do
            apt remove --purge -y "$kernel" 2>/dev/null || true
        done
        append_summary "Old kernel headers and modules cleaned up."
    else
        append_summary "No old kernels found to remove."
    fi
}

# --------------------------------------------------
# Main
# --------------------------------------------------


# Ensure script is run as root (or via sudo)
if [[ "${EUID:-$(id -u)}" -ne 0 ]]; then
    echo "This script requires sudo/root privileges. Attempting to re-run as sudo..."
    exec sudo bash "$0" "$@"
    echo "Unable to escalate privileges. Exiting."
    exit 1
fi

# (4) Validate Dependencies
check_dependencies

# (2) Disk Space Check
check_disk_space

# 1) Update/upgrade/autoremove
update_packages
full_upgrade
autoremove_packages

# 1.5) Cleanup tasks
cleanup_apt_cache
cleanup_old_logs
cleanup_old_kernels

# 2) If this is a Raspberry Pi, do Pi-specific tasks
if grep -q "Raspberry Pi" /proc/cpuinfo; then
    upgrade_firmware
    # Prompt to run unifi-update.sh
    read -rp "Do you want to run the unifi-update.sh script? [y/N]: " run_unifi
    if [[ "${run_unifi}" =~ ^[Yy]$ ]]; then
        if [[ -f "/home/doubleangels/unifi-update.sh" ]]; then
            print_section "Running unifi-update.sh..."
            chmod +x /home/doubleangels/unifi-update.sh
            bash /home/doubleangels/unifi-update.sh
            append_summary "Executed unifi-update.sh script."
        else
            echo -e "\n\e[1;31m'/home/doubleangels/unifi-update.sh' not found. Skipped.\e[0m"
        fi
    else
        append_summary "unifi-update.sh script skipped."
    fi
fi

# 3) If Docker is installed, run Docker maintenance
docker_maintenance

# 4) Handle fwupd firmware updates
fwupd_firmware_update

# 5) Check if a reboot is required
if [[ -f /var/run/reboot-required ]]; then
    echo -e "\n\e[1;31mA system reboot is required to complete updates. Reboot now? [y/N]: \e[0m"
    read -r reboot_now
    if [[ "${reboot_now}" =~ ^[Yy]$ ]]; then
        reboot
    fi
fi

# 6) Print summary
print_section "Updates Summary:"
echo -e "${UPDATES_SUMMARY}\n"
