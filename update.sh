#!/bin/bash -e

hostname=$(hostname)
updates_summary=""

# Parse options for verbose mode
verbose=false
while getopts "v" opt; do
    case ${opt} in
        v ) verbose=true ;;
    esac
done

# Enable verbose mode if specified
if $verbose; then set -x; fi

# Check if the script is not running as sudo
if [ "$EUID" -ne 0 ]; then
    echo "This script requires sudo privileges. Please enter your password to continue."
    exec sudo "$0" "$@"
    exit
fi

# Function to update package information
function update_packages() {
    echo -e "\n\e[1;33mUpdating package information...\e[0m"
    if sudo apt update; then
        updates_summary+="\n- Package information updated."
    else
        updates_summary+="\n- Package information update failed."
    fi
}

# Function to perform a full upgrade
function full_upgrade() {
    echo -e "\n\e[1;33mPerforming a full upgrade of installed packages...\e[0m"
    if sudo apt full-upgrade; then
        updates_summary+="\n- Full upgrade of installed packages performed."
    else
        updates_summary+="\n- Full upgrade failed."
    fi
}

# Function to remove unnecessary packages
function autoremove_packages() {
    echo -e "\n\e[1;33mRemoving unnecessary packages...\e[0m"
    if sudo apt autoremove; then
        updates_summary+="\n- Unnecessary packages removed."
    else
        updates_summary+="\n- Autoremove failed."
    fi
}

# Function to upgrade Raspberry Pi firmware
function upgrade_firmware() {
    echo -e "\n\e[1;33mUpgrading firmware...\e[0m"
    if ! command -v rpi-update &>/dev/null; then
        echo -e "\n\e[1;33mrpi-update is not installed, installing it...\e[0m"
        sudo apt-get update
        sudo apt-get install rpi-update -y
    fi
    read -p "Do you want to run firmware update (rpi-update)? [y/N]: " run_rpi_update
    if [[ $run_rpi_update =~ ^[Yy]$ ]]; then
        sudo rpi-update
        updates_summary+="\n- Firmware upgraded using rpi-update."
    else
        updates_summary+="\n- Firmware upgrade skipped."
    fi
}

# Function to handle Docker maintenance
function docker_maintenance() {
    if command -v docker &>/dev/null; then
        if [ -f "dockcheck.sh" ]; then
            echo -e "\n\e[1;33mRunning dockcheck.sh script with options to update stopped containers and restart stacks...\e[0m"
            sudo bash dockcheck.sh -apfs
            updates_summary+="\n- Ran dockcheck.sh script."
        else
            echo -e "\n\e[1;31mDockcheck.sh script not found. Attempting to download from the internet.\e[0m"
            if command -v curl &>/dev/null; then
                curl -o dockcheck.sh https://raw.githubusercontent.com/mag37/dockcheck/main/dockcheck.sh
                if [ -f "dockcheck.sh" ]; then
                    chmod +x dockcheck.sh
                    echo -e "\n\e[1;33mDockcheck.sh downloaded successfully. Running the script...\e[0m"
                    sudo bash dockcheck.sh -apfs
                    updates_summary+="\n- Downloaded and ran dockcheck.sh script."
                else
                    echo -e "\n\e[1;31mFailed to download dockcheck.sh. Skipping Docker maintenance.\e[0m"
                fi
            else
                echo -e "\n\e[1;31mCurl is not installed. Skipping Docker maintenance.\e[0m"
            fi
        fi
        
        # Automatically perform Docker prune with -fa arguments
        echo -e "\n\e[1;33mRemoving all unused Docker containers, networks, images, and volumes (forcing prune)...\e[0m"
        sudo docker system prune -fa
        updates_summary+="\n- Removed all unused Docker containers, networks, images, and volumes with force."
    fi
}

# Call functions to execute update tasks
update_packages
full_upgrade
autoremove_packages

# Run Raspberry Pi-specific updates if applicable
if grep -q "Raspberry Pi" /proc/cpuinfo; then
    upgrade_firmware
    echo -e "\n\e[1;33mGiving execute permissions and running unifi-update.sh...\e[0m"
    chmod +x /home/doubleangels/unifi-update.sh
    bash /home/doubleangels/unifi-update.sh
    updates_summary+="\n- Executed unifi-update.sh script."
fi

# Run Docker maintenance if Docker is installed
docker_maintenance

# Prompt for reboot if required
if [ -f /var/run/reboot-required ]; then
    echo -e "\n\e[1;31mA system reboot is required to complete updates. Reboot now? [y/N]: \e[0m"
    read -r reboot_now
    if [[ $reboot_now =~ ^[Yy]$ ]]; then
        sudo reboot
    fi
fi

# Summary of updates
echo -e "\n\e[1;33mUpdates Summary:$updates_summary\e[0m\n"