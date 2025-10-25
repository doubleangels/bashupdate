#!/usr/bin/env bash
#
# Comprehensive Update Script for Debian-based Systems
# Updates apt, installs necessary packages, upgrades system, and cleans up

# --------------------------------------------------
# Enable unofficial bash "strict mode":
# - e : Exit immediately if a command exits with a non-zero status
# - u : Treat unset variables as an error
# - o pipefail : Pipeline returns the exit status of the last command that had a non-zero exit code
# --------------------------------------------------
set -euo pipefail

# Check for sudo/root privileges
if [[ "${EUID:-$(id -u)}" -ne 0 ]]; then
    echo "This script requires root privileges. Attempting to re-run with sudo..."
    exec sudo bash "$0" "$@"
fi

# --------------------------------------------------
# Globals
# --------------------------------------------------
SCRIPT_NAME="$(basename "$0")"
HOSTNAME="$(hostname)"
UPDATES_SUMMARY=""
LOG_FILE="/var/log/update_script.log"
START_TIME=$(date +%s)

# --------------------------------------------------
# Utility Functions
# --------------------------------------------------

function print_section() {
    echo -e "\n\e[1;34m===============================================================\e[0m"
    echo -e "\e[1;34m\e[1;37m ${1} \e[0m\e[1;34m\e[0m"
    echo -e "\e[1;34m===============================================================\e[0m"
    echo "$(date '+%Y-%m-%d %H:%M:%S') - ${1}" >> "$LOG_FILE"
}

function print_info() {
    echo -e "  \e[1;32m▶\e[0m \e[1;37m${1}\e[0m"
    echo "$(date '+%Y-%m-%d %H:%M:%S') - [INFO] ${1}" >> "$LOG_FILE"
}

function print_warning() {
    echo -e "  \e[1;33m⚠\e[0m \e[1;33m${1}\e[0m"
    echo "$(date '+%Y-%m-%d %H:%M:%S') - [WARNING] ${1}" >> "$LOG_FILE"
}

function print_error() {
    echo -e "  \e[1;31m✗\e[0m \e[1;31m${1}\e[0m"
    echo "$(date '+%Y-%m-%d %H:%M:%S') - [ERROR] ${1}" >> "$LOG_FILE"
}

function append_summary() {
    UPDATES_SUMMARY+="\n- ${1}"
}

function log_command() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - Executing: $*" >> "$LOG_FILE"
}

# --------------------------------------------------
# Prerequisites and Validation
# --------------------------------------------------

function check_root_privileges() {
    if [[ "${EUID:-$(id -u)}" -ne 0 ]]; then
        print_error "This script requires root privileges. Please run with sudo."
        exit 1
    fi
}

function check_disk_space() {
    local required_kb=1048576  # 1GB
    local available_kb
    local formatted_size
    
    available_kb="$(df --output=avail / | tail -n1)"
    if (( available_kb < required_kb )); then
        print_error "Insufficient disk space available (less than 1GB). Exiting."
        exit 1
    fi
    
    # Format the available space in GB or MB
    if (( available_kb >= 1048576 )); then
        # Convert to GB
        local available_gb=$((available_kb / 1048576))
        local remaining_mb=$(((available_kb % 1048576) / 1024))
        if (( remaining_mb > 0 )); then
            formatted_size="${available_gb}.${remaining_mb}GB"
        else
            formatted_size="${available_gb}GB"
        fi
    else
        # Convert to MB
        local available_mb=$((available_kb / 1024))
        formatted_size="${available_mb}MB"
    fi
    
    print_info "Disk space check passed (${formatted_size} available)"
}

function check_dependencies() {
    local required_commands=("apt" "dpkg" "grep" "awk")
    
    for cmd in "${required_commands[@]}"; do
        if ! command -v "$cmd" &>/dev/null; then
            print_error "Required command '$cmd' is not available."
            exit 1
        fi
    done
    print_info "All required dependencies are available"
}

# --------------------------------------------------
# Package Management Functions
# --------------------------------------------------

function update_apt_packages() {
    print_section "Updating APT Package Lists"
    
    log_command "apt update"
    if apt update 2>&1 | tee -a "$LOG_FILE"; then
        print_info "APT package lists updated successfully"
        append_summary "APT package lists updated"
    else
        print_error "Failed to update APT package lists"
        append_summary "APT update failed"
        return 1
    fi
}

function install_necessary_packages() {
    print_section "Installing Script Dependencies"
    
    # Only install packages that are NOT typically included in Debian base install
    # but are needed for this script to function
    local packages=(
        "curl"             # For downloading dockcheck (not in base Debian)
    )
    
    local installed_count=0
    local skipped_count=0
    local failed_count=0
    
    for package in "${packages[@]}"; do
        if dpkg -l | grep -q "^ii.*$package "; then
            print_info "$package is already installed"
            skipped_count=$((skipped_count + 1))
        else
            print_info "Installing $package"
            log_command "apt install -y $package"
            if apt install -y "$package" 2>&1 | tee -a "$LOG_FILE"; then
                print_info "$package installed successfully"
                installed_count=$((installed_count + 1))
            else
                print_warning "Failed to install $package"
                failed_count=$((failed_count + 1))
            fi
        fi
    done
    
    append_summary "Package installation: $installed_count installed, $skipped_count already present, $failed_count failed"
}

function upgrade_system() {
    print_section "Upgrading System Packages"
    
    log_command "apt upgrade -y"
    if apt upgrade -y 2>&1 | tee -a "$LOG_FILE"; then
        print_info "System upgrade completed successfully"
        append_summary "System packages upgraded"
    else
        print_error "System upgrade failed"
        append_summary "System upgrade failed"
        return 1
    fi
}

function autoclean_and_purge() {
    print_section "Cleaning Up System"
    
    # Autoremove unused packages
    print_info "Removing unused packages"
    log_command "apt autoremove -y"
    if apt autoremove -y 2>&1 | tee -a "$LOG_FILE"; then
        print_info "Unused packages removed"
        append_summary "Unused packages removed"
    else
        print_warning "Failed to remove unused packages"
    fi
    
    # Clean APT cache
    print_info "Cleaning APT cache"
    log_command "apt clean"
    if apt clean 2>&1 | tee -a "$LOG_FILE"; then
        print_info "APT cache cleaned"
        append_summary "APT cache cleaned"
    else
        print_warning "Failed to clean APT cache"
    fi
    
    # Purge old packages
    print_info "Purging old packages"
    log_command "apt autoclean"
    if apt autoclean 2>&1 | tee -a "$LOG_FILE"; then
        print_info "Old packages purged"
        append_summary "Old packages purged"
    else
        print_warning "Failed to purge old packages"
    fi
}

# --------------------------------------------------
# System Maintenance
# --------------------------------------------------

function cleanup_old_kernels() {
    print_section "Cleaning Up Old Kernels"
    
    local current_kernel
    current_kernel=$(uname -r)
    print_info "Current kernel: $current_kernel"
    
    # Remove old kernel packages
    print_info "Checking for old kernels to remove"
    log_command "apt autoremove --purge -y"
    local autoremove_output
    autoremove_output=$(apt autoremove --purge -y 2>&1)
    echo "$autoremove_output" | tee -a "$LOG_FILE"
    
    if echo "$autoremove_output" | grep -q "0 upgraded, 0 newly installed, 0 to remove"; then
        print_info "No old kernel packages found to remove"
        append_summary "No old kernel packages to remove"
    else
        print_info "Old kernel packages removed"
        append_summary "Old kernel packages removed"
    fi
}

function cleanup_logs() {
    print_section "Cleaning Up Old Log Files"
    
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
        print_info "Removed $removed_count old log files"
        append_summary "Removed $removed_count old log files"
    else
        print_info "No old log files found"
        append_summary "No old log files to remove"
    fi
}

function docker_maintenance() {
    print_section "Docker Container Maintenance"
    
    # Check if Docker is installed
    if ! command -v docker &>/dev/null; then
        print_info "Docker not found. Skipping Docker maintenance."
        append_summary "Docker maintenance skipped (Docker not installed)"
        return 0
    fi
    
    # Check if curl is available for downloading dockcheck
    if ! command -v curl &>/dev/null; then
        print_warning "curl not available. Installing curl for dockcheck download"
        if apt install -y curl 2>&1 | tee -a "$LOG_FILE"; then
            print_info "curl installed successfully"
        else
            print_error "Failed to install curl. Skipping Docker maintenance."
            append_summary "Docker maintenance skipped (curl installation failed)"
            return 1
        fi
    fi
    
    # Download latest dockcheck.sh
    print_info "Downloading latest dockcheck.sh from GitHub"
    log_command "curl -o dockcheck.sh https://raw.githubusercontent.com/mag37/dockcheck/main/dockcheck.sh"
    if curl -o dockcheck.sh https://raw.githubusercontent.com/mag37/dockcheck/main/dockcheck.sh 2>&1 | tee -a "$LOG_FILE"; then
        if [[ -f "dockcheck.sh" ]]; then
            chmod +x dockcheck.sh
            print_info "dockcheck.sh downloaded and made executable"
            
            # Run dockcheck with options: -a (all), -p (pull), -f (force), -s (restart stacks)
            print_info "Running dockcheck.sh to update and restart Docker containers"
            log_command "bash ./dockcheck.sh -apfs"
            if bash ./dockcheck.sh -apfs 2>&1 | tee -a "$LOG_FILE"; then
                print_info "Docker containers updated and stacks restarted successfully"
                append_summary "Docker containers updated and stacks restarted"
            else
                print_warning "dockcheck.sh completed with warnings or errors"
                append_summary "Docker maintenance completed with warnings"
            fi
            
            # Clean up dockcheck.sh file
            rm -f dockcheck.sh
            print_info "Cleaned up dockcheck.sh file"
        else
            print_error "dockcheck.sh file not found after download"
            append_summary "Docker maintenance failed (file not found)"
            return 1
        fi
    else
        print_error "Failed to download dockcheck.sh from GitHub"
        append_summary "Docker maintenance failed (download failed)"
        return 1
    fi
    
    # Comprehensive Docker cleanup - purge all unused resources
    print_info "Performing comprehensive Docker cleanup"
    
    # Remove all unused containers
    print_info "Removing unused containers"
    log_command "docker container prune -f"
    if docker container prune -f 2>&1 | tee -a "$LOG_FILE" | grep -q "Total reclaimed space: 0B"; then
        print_info "No unused containers found"
    else
        print_info "Unused containers removed"
    fi
    sleep 1
    
    # Remove all unused volumes
    print_info "Removing unused volumes"
    log_command "docker volume prune -f"
    if docker volume prune -f 2>&1 | tee -a "$LOG_FILE" | grep -q "Total reclaimed space: 0B"; then
        print_info "No unused volumes found"
    else
        print_info "Unused volumes removed"
    fi
    sleep 1
    
    # Remove all unused networks
    print_info "Removing unused networks"
    log_command "docker network prune -f"
    if docker network prune -f 2>&1 | tee -a "$LOG_FILE" | grep -q "Total reclaimed space: 0B"; then
        print_info "No unused networks found"
    else
        print_info "Unused networks removed"
    fi
    sleep 1
    
    # Remove all unused images
    print_info "Removing unused images"
    log_command "docker image prune -a -f"
    if docker image prune -a -f 2>&1 | tee -a "$LOG_FILE" | grep -q "Total reclaimed space: 0B"; then
        print_info "No unused images found"
    else
        print_info "Unused images removed"
    fi
    sleep 1
    
    # Final system prune for any remaining resources
    print_info "Performing final system cleanup"
    log_command "docker system prune -a -f --volumes"
    if docker system prune -a -f --volumes 2>&1 | tee -a "$LOG_FILE" | grep -q "Total reclaimed space: 0B"; then
        print_info "No additional cleanup needed"
    else
        print_info "Additional system cleanup completed"
    fi
    
    print_info "Comprehensive Docker cleanup completed"
    append_summary "Docker cleanup: containers, volumes, networks, and images checked"
}

# --------------------------------------------------
# Summary and Reporting
# --------------------------------------------------

function print_summary() {
    local end_time=$(date +%s)
    local duration=$((end_time - START_TIME))
    local duration_formatted=$(printf "%02d:%02d:%02d" $((duration/3600)) $((duration%3600/60)) $((duration%60)))
    
    print_section "Update Summary"
    echo -e "\e[1;34m┌─ Summary of Actions Performed ─────────────────────────────────┐\e[0m"
    echo -e "${UPDATES_SUMMARY}"
    echo -e "\e[1;34m└─────────────────────────────────────────────────────────────────┘\e[0m"
    print_info "Script completed in $duration_formatted"
    print_info "Full log available at: $LOG_FILE"
    
    # Check if reboot is required
    if [[ -f /var/run/reboot-required ]]; then
        print_warning "System reboot is required to complete updates"
        echo -e "\n\e[1;33mDo you want to reboot now? [y/N]: \e[0m"
        read -r reboot_now
        if [[ "${reboot_now}" =~ ^[Yy]$ ]]; then
            print_info "Rebooting system"
            reboot
        else
            print_info "Please reboot manually when convenient"
        fi
    fi
}

# --------------------------------------------------
# Main Execution
# --------------------------------------------------

function main() {
    print_section "Starting System Update Process"
    print_info "Script: $SCRIPT_NAME"
    print_info "Host: $HOSTNAME"
    print_info "Started at: $(date)"
    
    # Initialize log file
    echo "=== Update Script Started at $(date) ===" > "$LOG_FILE"
    
    # Run all update functions
    check_root_privileges
    check_dependencies
    check_disk_space
    
    update_apt_packages
    install_necessary_packages
    upgrade_system
    autoclean_and_purge
    cleanup_old_kernels
    cleanup_logs
    docker_maintenance
    
    # Check if this is a Raspberry Pi and prompt for unifi-update.sh
    print_section "Checking for Raspberry Pi specific tasks"
    if grep -q "Raspberry Pi" /proc/cpuinfo; then
        print_info "Raspberry Pi detected"
        echo -e "\n\e[1;33mDo you want to run the unifi-update.sh script? [y/N]: \e[0m"
        read -t 30 -rp "" run_unifi || run_unifi="N"
        if [[ "${run_unifi}" =~ ^[Yy]$ ]]; then
            if [[ -f "/home/doubleangels/unifi-update.sh" ]]; then
                print_info "Running unifi-update.sh"
                chmod +x /home/doubleangels/unifi-update.sh
                bash /home/doubleangels/unifi-update.sh
                append_summary "Executed unifi-update.sh script"
            else
                print_warning "unifi-update.sh script not found at /home/doubleangels/unifi-update.sh"
                append_summary "unifi-update.sh script not found"
            fi
        else
            print_info "unifi-update.sh script skipped"
            append_summary "unifi-update.sh script skipped"
        fi
    else
        print_info "Not a Raspberry Pi system"
        append_summary "Pi-specific tasks skipped (not a Raspberry Pi)"
    fi
    
    print_summary
}

# Execute main function
main "$@"
