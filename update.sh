#!/usr/bin/env bash
#
# A simple update & maintenance script for Raspberry Pi (or Debian-based systems).
# Usage:
#   ./update.sh [-v]
#
# Options:
#   -v    Enable verbose output (set -x).

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
VERBOSE=false

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
# Handle Docker maintenance
# --------------------------------------------------
function docker_maintenance() {
    if command -v docker &>/dev/null; then
        if [[ -f "./dockcheck.sh" ]]; then
            print_section "Running dockcheck.sh (updating stopped containers and restarting stacks)..."
            bash ./dockcheck.sh -apfs
            append_summary "Ran dockcheck.sh script."
        else
            echo -e "\n\e[1;31m'dockcheck.sh' not found locally. Attempting download from the internet.\e[0m"
            if command -v curl &>/dev/null; then
                curl -o dockcheck.sh \
                    https://raw.githubusercontent.com/mag37/dockcheck/main/dockcheck.sh
                if [[ -f "dockcheck.sh" ]]; then
                    chmod +x dockcheck.sh
                    print_section "Dockcheck.sh downloaded. Running it now..."
                    bash ./dockcheck.sh -apfs -x 4
                    append_summary "Downloaded and ran dockcheck.sh script."
                else
                    echo -e "\n\e[1;31mFailed to download dockcheck.sh. Skipping Docker maintenance.\e[0m"
                fi
            else
                echo -e "\n\e[1;31mcurl is not installed. Skipping Docker maintenance.\e[0m"
            fi
        fi

        # Automatically prune Docker resources
        print_section "Removing all unused Docker containers, networks, images, and volumes (forced prune)..."
        docker system prune -fa
        append_summary "Removed all unused Docker containers, networks, images, and volumes (force)."
    fi
}

# --------------------------------------------------
# Main
# --------------------------------------------------

# Parse command line options
while getopts "v" opt; do
    case "${opt}" in
        v) VERBOSE=true ;;
        *) ;;
    esac
done

# Enable verbose mode if specified
if ${VERBOSE}; then
    set -x
fi

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

# 4) Check if a reboot is required
if [[ -f /var/run/reboot-required ]]; then
    echo -e "\n\e[1;31mA system reboot is required to complete updates. Reboot now? [y/N]: \e[0m"
    read -r reboot_now
    if [[ "${reboot_now}" =~ ^[Yy]$ ]]; then
        reboot
    fi
fi

# 5) Print summary
print_section "Updates Summary:"
echo -e "${UPDATES_SUMMARY}\n"
